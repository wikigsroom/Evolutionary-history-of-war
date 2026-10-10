package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/jackc/pgx/v5"
)

func (s *Server) ticketHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		var kind, id string
		if err := tx.QueryRow(r.Context(), "SELECT activity_kind,activity_id FROM online_players WHERE id=$1", player).Scan(&kind, &id); err != nil {
			return nil, err
		}
		if kind != "match" {
			return nil, invalid("NO_ACTIVE_MATCH")
		}
		if stringValue(b["match_id"]) != id {
			return nil, invalid("MATCH_CHANGED")
		}
		ticket := secret()
		_, err := tx.Exec(r.Context(), "INSERT INTO online_ws_tickets(hash,player_id,match_id,expires_at) VALUES($1,$2,$3,now()+interval '30 seconds')", digest([]byte(ticket)), player, id)
		return Object{"ok": true, "ticket": ticket, "socket_path": "/v1/socket", "expires_in": 30, "match_id": id}, err
	})
}

func (s *Server) socketHTTP(w http.ResponseWriter, r *http.Request) {
	ticket := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if len(ticket) != 64 {
		errorResponse(w, failure("UNAUTHORIZED", 401))
		return
	}
	var player, id string
	err := s.store.pool.QueryRow(r.Context(), "UPDATE online_ws_tickets SET consumed=true WHERE hash=$1 AND NOT consumed AND expires_at>now() RETURNING player_id,match_id", digest([]byte(ticket))).Scan(&player, &id)
	if err != nil {
		errorResponse(w, failure("TICKET_EXPIRED", 401))
		return
	}
	// HTTP deadlines protect finite requests. A hijacked socket must use its own
	// heartbeat and per-write deadlines rather than inheriting the 10/15-second limits.
	controller := http.NewResponseController(w)
	if controller.SetReadDeadline(time.Time{}) != nil || controller.SetWriteDeadline(time.Time{}) != nil {
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{Subprotocols: []string{"epoch-rush.v1"}, CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	if conn.Subprotocol() != "epoch-rush.v1" {
		_ = conn.Close(websocket.StatusPolicyViolation, "subprotocol required")
		return
	}
	conn.SetReadLimit(8192)
	ctx, cancel := context.WithCancel(s.ctx)
	defer cancel()
	defer conn.CloseNow()
	var epoch int64
	var seat int
	err = s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil {
			return err
		}
		seat = row.Control.seatFor(player)
		if seat < 0 {
			return failure("NOT_MEMBER", 403)
		}
		control := &row.Control.Seats[seat]
		epoch = control.Epoch + 1
		control.Epoch = epoch
		control.GatewayID = s.instance
		control.LastSeenMS = nowMillis()
		if control.Connected {
			disconnectSeat(control, nowMillis())
		}
		// Cancel all received but uncommitted old clicks under the same match lock.
		if _, err = tx.Exec(ctx, "UPDATE online_commands SET status='CANCELLED_NOT_EXECUTED',result=jsonb_build_object('ok',false,'reason','RECONNECTED','status','CANCELLED_NOT_EXECUTED','client_seq',client_seq) WHERE match_id=$1 AND player_id=$2 AND status='PENDING'", id, player); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE online_matches SET control=$2 WHERE id=$1", id, encode(row.Control))
		return err
	})
	if err != nil {
		return
	}
	defer s.socketGone(id, player, epoch)
	write := func(value Object) error {
		c, done := context.WithTimeout(ctx, 2*time.Second)
		defer done()
		return conn.Write(c, websocket.MessageText, encode(value))
	}
	if err = write(Object{"v": "1.0", "type": "hello", "match_id": id, "connection_epoch": epoch, "payload": Object{"seat": seat}}); err != nil {
		return
	}
	// 128 × 8 KiB frames bound the queued input; backpressure absorbs a duplicate burst.
	input := make(chan Object, 128)
	readError := make(chan error, 1)
	go func() {
		for {
			_, raw, err := conn.Read(ctx)
			if err != nil {
				select {
				case readError <- err:
				default:
				}
				return
			}
			var msg Object
			if err = json.Unmarshal(raw, &msg); err != nil {
				select {
				case readError <- err:
				default:
				}
				return
			}
			select {
			case input <- msg:
			case <-ctx.Done():
				return
			}
		}
	}()
	stateTimer := time.NewTicker(100 * time.Millisecond)
	defer stateTimer.Stop()
	lastSeen := time.Now()
	lastPresence := time.Time{}
	lastBatch := int64(-1)
	acked := int64(-1)
	cache := map[int64]Object{}
	first := true
	lastStatus := time.Time{}
	sentResults := map[int64]bool{}
	for {
		select {
		case <-ctx.Done():
			return
		case <-readError:
			return
		case msg := <-input:
			if msg["v"] != "1.0" || msg["match_id"] != id || number(msg["connection_epoch"]) != epoch {
				return
			}
			lastSeen = time.Now()
			payload := object(msg["payload"])
			switch stringValue(msg["type"]) {
			case "ping":
				if time.Since(lastPresence) >= time.Second {
					if err = s.touchSeat(ctx, id, player, epoch, false); err != nil {
						return
					}
					lastPresence = time.Now()
				}
				if err = write(Object{"v": "1.0", "type": "pong", "match_id": id, "connection_epoch": epoch, "payload": payload}); err != nil {
					return
				}
			case "state_ack":
				seq := number(payload["snapshot_seq"])
				if _, ok := cache[seq]; ok {
					acked = seq
				}
			case "full_sync":
				first = true
				acked = -1
			case "resume_ready":
				result, err := s.resumeReady(ctx, id, player, epoch, payload)
				if err != nil {
					if write(Object{"v": "1.0", "type": "error", "payload": describeError(err)}) != nil {
						return
					}
					continue
				}
				if err = write(Object{"v": "1.0", "type": "resume_ready", "match_id": id, "connection_epoch": epoch, "payload": result}); err != nil {
					return
				}
			case "command":
				result, err := s.acceptCommand(ctx, id, player, epoch, payload)
				if err != nil {
					result = describeError(err)
					result["client_seq"] = payload["client_seq"]
				}
				if err = write(Object{"v": "1.0", "type": "command_receipt", "match_id": id, "connection_epoch": epoch, "payload": result}); err != nil {
					return
				}
			case "command_abandon":
				result, err := s.abandonCommand(ctx, id, player, epoch, payload)
				if err != nil {
					result = describeError(err)
				}
				if err = write(Object{"v": "1.0", "type": "command_result", "match_id": id, "connection_epoch": epoch, "payload": result}); err != nil {
					return
				}
			case "suspend":
				if err = s.setDisconnected(ctx, id, player, epoch); err != nil {
					return
				}
			default:
				return
			}
		case <-stateTimer.C:
			if time.Since(lastSeen) > 8*time.Second {
				return
			}
			row, err := loadMatch(ctx, s.store.pool, id, false)
			if err != nil {
				continue
			}
			if row.Control.Seats[seat].Epoch != epoch {
				return
			}
			if row.Phase == "FINISHED" {
				result, err := s.matchResult(ctx, s.store.pool, id)
				if err != nil {
					continue
				}
				if write(Object{"v": "1.0", "type": "match_result", "match_id": id, "connection_epoch": epoch, "payload": result}) != nil {
					return
				}
				_ = conn.Close(websocket.StatusNormalClosure, "match finished")
				return
			}
			if len(row.Projections) != 2 {
				continue
			}
			if row.Batch == lastBatch && !first {
				if time.Since(lastStatus) >= time.Second {
					lastStatus = time.Now()
					if err = write(Object{"v": "1.0", "type": "connection_status", "match_id": id, "connection_epoch": epoch, "payload": connectionProjection(row, seat)}); err != nil {
						return
					}
				}
				continue
			}
			lastBatch = row.Batch
			state := row.Projections[seat]
			state["connection"] = connectionProjection(row, seat)
			state["snapshot_seq"] = row.Batch
			state["next_client_seq"] = row.Control.Seats[seat].NextSeq
			base, known := cache[acked]
			packet := Object{"v": "1.0", "type": "state_full", "match_id": id, "connection_epoch": epoch, "payload": state}
			if !first && known {
				delta := Object{}
				for k, v := range state {
					if digest(encode(v)) != digest(encode(base[k])) {
						delta[k] = v
					}
				}
				packet["type"] = "state_delta"
				packet["payload"] = Object{"base_snapshot_seq": acked, "snapshot_seq": row.Batch, "changes": delta}
			}
			encoded := encode(packet)
			if len(encoded) > 32768 && packet["type"] == "state_delta" {
				packet["type"] = "state_full"
				packet["payload"] = state
				encoded = encode(packet)
			}
			if len(encoded) > 262144 {
				return
			}
			if len(encoded) > 32768 {
				hash := digest(encoded)
				parts := (len(encoded) + 16383) / 16384
				for i := 0; i < parts; i++ {
					end := (i + 1) * 16384
					if end > len(encoded) {
						end = len(encoded)
					}
					if err = write(Object{"v": "1.0", "type": "state_chunk", "match_id": id, "connection_epoch": epoch, "payload": Object{"snapshot_seq": row.Batch, "index": i, "count": parts, "hash": hash, "data": base64.StdEncoding.EncodeToString(encoded[i*16384 : end])}}); err != nil {
						return
					}
				}
			} else if err = write(packet); err != nil {
				return
			}
			cache[row.Batch] = state
			for seq := range cache {
				if seq < row.Batch-8 && seq != acked {
					delete(cache, seq)
				}
			}
			first = false
			results, err := s.commandResults(ctx, s.store.pool, id, player)
			if err != nil {
				continue
			}
			for _, result := range results {
				seq := number(result["client_seq"])
				if sentResults[seq] {
					continue
				}
				if err = write(Object{"v": "1.0", "type": "command_result", "match_id": id, "connection_epoch": epoch, "payload": result}); err != nil {
					return
				}
				sentResults[seq] = true
			}
			if len(sentResults) > 128 {
				live := map[int64]bool{}
				for _, result := range results {
					live[number(result["client_seq"])] = true
				}
				sentResults = live
			}
		}
	}
}

func connectionProjection(row *MatchRow, seat int) Object {
	other := row.Control.Seats[1-seat]
	remaining := int64(120000)
	if other.OfflineSinceMS > 0 {
		remaining -= nowMillis() - other.OfflineSinceMS
	}
	if remaining < 0 {
		remaining = 0
	}
	return Object{"phase": row.Phase, "paused": row.Control.Paused || row.Phase != "RUNNING", "pause_reason": row.Control.PauseReason, "opponent_connected": other.Connected, "opponent_grace_ms": remaining, "server_recovering": row.Control.PauseReason == "SERVER_RECOVERING" || time.Since(rowUpdatedTime(row)) > time.Second}
}
func rowUpdatedTime(row *MatchRow) time.Time { return row.Lease.Add(-6 * time.Second) }
func (s *Server) touchSeat(ctx context.Context, id, player string, epoch int64, loaded bool) error {
	return s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil {
			return err
		}
		seat := row.Control.seatFor(player)
		if seat < 0 || row.Control.Seats[seat].Epoch != epoch {
			return invalid("STALE_CONNECTION")
		}
		c := &row.Control.Seats[seat]
		c.LastSeenMS = nowMillis()
		if loaded {
			c.Loaded = true
			c.Connected = true
			c.OfflineSinceMS = 0
			c.PauseUntilMS = 0
		}
		_, err = tx.Exec(ctx, "UPDATE online_matches SET control=$2 WHERE id=$1", id, encode(row.Control))
		return err
	})
}
func (s *Server) setDisconnected(ctx context.Context, id, player string, epoch int64) error {
	return s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil {
			return err
		}
		seat := row.Control.seatFor(player)
		if seat < 0 || row.Control.Seats[seat].Epoch != epoch {
			return nil
		}
		disconnectSeat(&row.Control.Seats[seat], nowMillis())
		_, err = tx.Exec(ctx, "UPDATE online_matches SET control=$2 WHERE id=$1", id, encode(row.Control))
		return err
	})
}
func (s *Server) socketGone(id, player string, epoch int64) {
	ctx, c := context.WithTimeout(context.Background(), 2*time.Second)
	defer c()
	_ = s.setDisconnected(ctx, id, player, epoch)
}

func (s *Server) resumeReady(ctx context.Context, id, player string, epoch int64, payload Object) (Object, error) {
	if list, ok := payload["pending_sequences"].([]any); ok {
		if len(list) > 64 {
			return nil, failure("TOO_MANY_PENDING", 400)
		}
		seqs := make([]int64, 0, len(list))
		for _, x := range list {
			seqs = append(seqs, number(x))
		}
		sort.Slice(seqs, func(i, j int) bool { return seqs[i] < seqs[j] })
		for _, seq := range seqs {
			if _, err := s.abandonCommand(ctx, id, player, epoch, Object{"client_seq": float64(seq)}); err != nil {
				return nil, err
			}
		}
	}
	if err := s.touchSeat(ctx, id, player, epoch, true); err != nil {
		return nil, err
	}
	row, err := loadMatch(ctx, s.store.pool, id, false)
	if err != nil {
		return nil, err
	}
	results, err := s.commandResults(ctx, s.store.pool, id, player)
	if err != nil {
		return nil, err
	}
	return Object{"ok": true, "next_client_seq": row.Control.Seats[row.Control.seatFor(player)].NextSeq, "results": results}, nil
}
func (s *Server) commandResults(ctx context.Context, q Querier, id, player string) ([]Object, error) {
	rows, err := q.Query(ctx, "SELECT result FROM online_commands WHERE match_id=$1 AND player_id=$2 AND status!='PENDING' ORDER BY client_seq DESC LIMIT 64", id, player)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []Object{}
	for rows.Next() {
		var raw []byte
		_ = rows.Scan(&raw)
		var result Object
		_ = json.Unmarshal(raw, &result)
		results = append(results, result)
	}
	return results, rows.Err()
}
func (s *Server) acceptCommand(ctx context.Context, id, player string, epoch int64, payload Object) (Object, error) {
	seq, err := integer(payload, "client_seq", 1, 100000000)
	if err != nil {
		return nil, err
	}
	action, ok := payload["action"].(map[string]any)
	if !ok || len(encode(action)) > 2048 {
		return nil, failure("INVALID_ACTION", 400)
	}
	if _, ok = action["side"]; ok {
		return nil, failure("INVALID_FIELD", 400)
	}
	if _, ok = action["hp"]; ok {
		return nil, failure("INVALID_FIELD", 400)
	}
	allowed := map[string]bool{"train": true, "cancel": true, "evolve": true, "research": true, "turret": true, "sell": true, "unlockSlot": true, "stance": true, "item": true, "ageSpecial": true, "cast": true}
	if !allowed[stringValue(action["type"])] {
		return nil, failure("INVALID_ACTION", 400)
	}
	hash := digest(encode(action))
	var result Object
	err = s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil {
			return err
		}
		seat := row.Control.seatFor(player)
		if seat < 0 {
			return failure("NOT_MEMBER", 403)
		}
		control := &row.Control.Seats[seat]
		if control.Epoch != epoch {
			return invalid("STALE_CONNECTION")
		}
		var oldHash, status string
		var raw []byte
		err = tx.QueryRow(ctx, "SELECT payload_hash,status,result FROM online_commands WHERE match_id=$1 AND player_id=$2 AND client_seq=$3", id, player, seq).Scan(&oldHash, &status, &raw)
		if err == nil {
			if oldHash != hash {
				return invalid("IDEMPOTENCY_CONFLICT")
			}
			if status == "PENDING" {
				result = Object{"ok": true, "status": "QUEUED", "client_seq": seq}
			} else {
				_ = json.Unmarshal(raw, &result)
			}
			return nil
		}
		if err != pgx.ErrNoRows {
			return err
		}
		if row.Phase != "RUNNING" || !control.Connected {
			return invalid("INPUT_LOCKED")
		}
		if seq != control.NextSeq {
			return invalid("SEQUENCE_GAP")
		}
		lastTick, err := integer(payload, "last_seen_tick", 0, 100000000)
		if err != nil {
			return err
		}
		if lastTick > row.Tick || row.Tick-lastTick > 60 {
			return invalid("STALE_VIEW")
		}
		var recent, pending int
		err = tx.QueryRow(ctx, "SELECT count(*) FILTER(WHERE received_at>now()-interval '1 second'),count(*) FILTER(WHERE status='PENDING') FROM online_commands WHERE match_id=$1 AND player_id=$2", id, player).Scan(&recent, &pending)
		if err != nil {
			return err
		}
		if recent >= 40 || pending >= 64 {
			return failure("RATE_LIMITED", 429)
		}
		ttl := int64(2000)
		if stringValue(action["type"]) == "cast" || stringValue(action["type"]) == "ageSpecial" || (stringValue(action["type"]) == "item" && action["itemId"] == "smoke-bomb") {
			ttl = 500
		}
		_, err = tx.Exec(ctx, "INSERT INTO online_commands(match_id,player_id,client_seq,payload,payload_hash,connection_epoch,apply_tick,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()+$8*interval '1 millisecond')", id, player, seq, encode(action), hash, epoch, row.Tick+2, ttl)
		if err != nil {
			return err
		}
		control.NextSeq++
		control.LastSeenMS = nowMillis()
		_, err = tx.Exec(ctx, "UPDATE online_matches SET control=$2 WHERE id=$1", id, encode(row.Control))
		result = Object{"ok": true, "status": "QUEUED", "client_seq": seq}
		return err
	})
	return result, err
}
func (s *Server) abandonCommand(ctx context.Context, id, player string, epoch int64, payload Object) (Object, error) {
	seq, err := integer(payload, "client_seq", 1, 100000000)
	if err != nil {
		return nil, err
	}
	var result Object
	err = s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil {
			return err
		}
		seat := row.Control.seatFor(player)
		if seat < 0 || row.Control.Seats[seat].Epoch != epoch {
			return invalid("STALE_CONNECTION")
		}
		c := &row.Control.Seats[seat]
		var raw []byte
		var status string
		err = tx.QueryRow(ctx, "SELECT status,result FROM online_commands WHERE match_id=$1 AND player_id=$2 AND client_seq=$3", id, player, seq).Scan(&status, &raw)
		if err == nil && status != "PENDING" {
			_ = json.Unmarshal(raw, &result)
			return nil
		}
		if err != nil && err != pgx.ErrNoRows {
			return err
		}
		result = Object{"ok": false, "status": "CANCELLED_NOT_EXECUTED", "client_seq": seq, "reason": "OLD_INPUT_CANCELLED"}
		if err == pgx.ErrNoRows {
			if seq != c.NextSeq {
				return invalid("SEQUENCE_GAP")
			}
			_, err = tx.Exec(ctx, "INSERT INTO online_commands(match_id,player_id,client_seq,payload,payload_hash,connection_epoch,status,apply_tick,expires_at,result) VALUES($1,$2,$3,'{}','abandoned',$4,'CANCELLED_NOT_EXECUTED',$5,now(),$6)", id, player, seq, epoch, row.Tick, encode(result))
			if err != nil {
				return err
			}
			c.NextSeq++
			_, err = tx.Exec(ctx, "UPDATE online_matches SET control=$2 WHERE id=$1", id, encode(row.Control))
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE online_commands SET status='CANCELLED_NOT_EXECUTED',result=$4 WHERE match_id=$1 AND player_id=$2 AND client_seq=$3", id, player, seq, encode(result))
		return err
	})
	return result, err
}
