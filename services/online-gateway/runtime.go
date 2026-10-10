package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
)

func (s *Server) supervise() {
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-timer.C:
			s.updateDrain()
			_, err := s.store.pool.Exec(s.ctx, "INSERT INTO online_gateways(id,last_seen,draining) VALUES($1,now(),$2) ON CONFLICT(id) DO UPDATE SET last_seen=now(),draining=$2", s.instance, s.draining.Load())
			if err != nil {
				continue
			}
			rows, err := s.store.pool.Query(s.ctx, "SELECT id FROM online_matches WHERE phase!='FINISHED' AND simulation_hash=$1 AND (owner_id=$2 OR lease_until<now())", s.rules.Manifest["simulation_hash"], s.instance)
			if err != nil {
				continue
			}
			var ids []string
			for rows.Next() {
				var id string
				_ = rows.Scan(&id)
				ids = append(ids, id)
			}
			rows.Close()
			// Old builds are allowed to finish on their original healthy owner. An orphaned
			// build cannot be simulated with different rules and closes without a winner.
			s.abortUnsupportedBuilds()
			for _, id := range ids {
				s.mu.Lock()
				running := s.runtimes[id]
				if !running {
					s.runtimes[id] = true
				}
				s.mu.Unlock()
				if !running {
					go s.runMatch(id)
				}
			}
		}
	}
}

func (s *Server) updateDrain() {
	if s.drainFile == "" {
		return
	}
	_, err := os.Stat(s.drainFile)
	s.draining.Store(err == nil)
}

func (s *Server) runMatch(id string) {
	defer func() { s.mu.Lock(); delete(s.runtimes, id); s.mu.Unlock() }()
	worker, err := startWorker(s.godot, s.project, id)
	if err != nil {
		log.Printf("worker_start_failed match=%s", id)
		s.recordRecoveryFailure(id)
		return
	}
	defer worker.close()
	var epoch int64
	err = s.store.transaction(s.ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(s.ctx, tx, id, true)
		if err != nil {
			return err
		}
		if row.Phase == "FINISHED" {
			return fmt.Errorf("finished")
		}
		if row.Owner != s.instance && row.Lease.After(time.Now()) {
			return fmt.Errorf("owned")
		}
		epoch = row.OwnerEpoch + 1
		var response *WorkerResponse
		if len(row.Snapshot) > 0 {
			raw, err := restoreSnapshot(row)
			if err != nil {
				return err
			}
			var snapshot Object
			if err = json.Unmarshal(raw, &snapshot); err != nil {
				return err
			}
			response, err = worker.request(Object{"type": "restore", "snapshot": snapshot})
		} else {
			response, err = worker.request(Object{"type": "init", "seed": row.Control.Seed, "loadouts": []Object{row.Control.Seats[0].Loadout, row.Control.Seats[1].Loadout}})
		}
		if err != nil {
			return err
		}
		// First public tick is also durable, before either client can operate.
		row.Owner = s.instance
		row.OwnerEpoch = epoch
		row.Control.RecoveryStartedMS = 0
		if nowMillis()-row.Control.LastAccountedMS > 1500 {
			_, _, _ = accountControl(&row.Control, row.Phase, nowMillis())
		}
		return s.persistBatch(s.ctx, tx, row, response, false)
	})
	if err != nil {
		log.Printf("worker_claim_failed match=%s", id)
		s.recordRecoveryFailure(id)
		return
	}
	timer := time.NewTicker(100 * time.Millisecond)
	defer timer.Stop()
	lastSimulation := time.Now()
	tickBudget := 0.0
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-timer.C:
			now := time.Now()
			elapsed := now.Sub(lastSimulation).Seconds()
			lastSimulation = now
			if elapsed > 1 {
				tickBudget = 0
			} else {
				tickBudget += elapsed * 30
			}
			if tickBudget > 15 {
				tickBudget = 15
			}
			finished := false
			err = s.store.transaction(s.ctx, func(tx pgx.Tx) error {
				row, err := loadMatch(s.ctx, tx, id, true)
				if err != nil {
					return err
				}
				if row.Phase == "FINISHED" {
					finished = true
					return nil
				}
				if row.Owner != s.instance || row.OwnerEpoch != epoch {
					return fmt.Errorf("lease fenced")
				}
				if row.Lease.Before(time.Now()) {
					return fmt.Errorf("lease expired")
				}
				gateways := map[string]bool{}
				for _, seat := range row.Control.Seats {
					if seat.Loaded && seat.GatewayID != "" {
						gateways[seat.GatewayID] = true
					}
				}
				ids := []string{}
				for gateway := range gateways {
					ids = append(ids, gateway)
				}
				var healthy int
				if err = tx.QueryRow(s.ctx, "SELECT count(*) FROM online_gateways WHERE id=ANY($1) AND last_seen>now()-interval '4 seconds'", ids).Scan(&healthy); err != nil {
					return err
				}
				phase, winner, reason := row.Phase, -1, ""
				if healthy < len(ids) {
					phase, winner, reason = platformPause(&row.Control, row.Phase, nowMillis())
				} else {
					row.Control.PlatformSinceMS = 0
					phase, winner, reason = accountControl(&row.Control, row.Phase, nowMillis())
				}
				row.Phase = phase
				rows, err := tx.Query(s.ctx, "SELECT player_id,client_seq,payload,apply_tick,expires_at FROM online_commands WHERE match_id=$1 AND status='PENDING' ORDER BY apply_tick,player_id,client_seq LIMIT 128", id)
				if err != nil {
					return err
				}
				commands := []Object{}
				type rejected struct {
					player string
					seq    int64
					reason string
				}
				rejects := []rejected{}
				for rows.Next() {
					var player string
					var seq, apply int64
					var raw []byte
					var expires time.Time
					if err = rows.Scan(&player, &seq, &raw, &apply, &expires); err != nil {
						rows.Close()
						return err
					}
					side := row.Control.seatFor(player)
					var action Object
					_ = json.Unmarshal(raw, &action)
					if reason != "" || row.Control.Paused {
						rejects = append(rejects, rejected{player, seq, "GAME_PAUSED"})
						continue
					}
					if time.Now().After(expires) {
						rejects = append(rejects, rejected{player, seq, "COMMAND_EXPIRED"})
						continue
					}
					commands = append(commands, Object{"player_id": player, "client_seq": seq, "action": action, "side": side, "apply_tick": apply})
				}
				rows.Close()
				// Alternate same-tick side priority; each player's own sequence remains ordered.
				sortCommands(commands, row.Tick)
				steps := int(tickBudget)
				tickBudget -= float64(steps)
				if row.Control.Paused || reason != "" {
					steps = 0
					tickBudget = 0
				}
				response, err := worker.request(Object{"type": "batch", "steps": steps, "commands": commands})
				if err != nil {
					return err
				}
				for _, reject := range rejects {
					response.Results = append(response.Results, struct {
						PlayerID string `json:"player_id"`
						Seq      int64  `json:"client_seq"`
						Result   Object `json:"result"`
						Tick     int64  `json:"tick"`
					}{reject.player, reject.seq, Object{"ok": false, "reason": reject.reason}, row.Tick})
				}
				if response.Winner >= 0 {
					winner = response.Winner
					reason = "BASE_DESTROYED"
					if response.Tick >= 72000 && winner == 2 {
						reason = "TIME_LIMIT"
					}
				}
				if reason != "" {
					if err = s.finishMatch(s.ctx, tx, row, winner, reason, response.Tick); err != nil {
						return err
					}
					finished = true
					response.Winner = winner
					var snapshot Object
					_ = json.Unmarshal(response.Snapshot, &snapshot)
					snapshot["winner"] = winner
					response.Snapshot = encode(snapshot)
					for _, p := range response.Projections {
						p["winner"] = winner
						p["result_reason"] = reason
					}
				}
				if row.Lease.Before(time.Now()) {
					return fmt.Errorf("lease expired during batch")
				}
				return s.persistBatch(s.ctx, tx, row, response, true)
			})
			if err != nil {
				log.Printf("match_recovering match=%s epoch=%d", id, epoch)
				s.recordRecoveryFailure(id)
				return
			}
			if finished {
				return
			}
		}
	}
}

func (s *Server) abortUnsupportedBuilds() {
	rows, err := s.store.pool.Query(s.ctx, "SELECT id FROM online_matches WHERE phase!='FINISHED' AND simulation_hash!=$1 AND lease_until<now()-interval '30 seconds' LIMIT 100", s.rules.Manifest["simulation_hash"])
	if err != nil {
		return
	}
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	for _, id := range ids {
		_ = s.store.transaction(s.ctx, func(tx pgx.Tx) error {
			row, err := loadMatch(s.ctx, tx, id, true)
			if err != nil {
				return err
			}
			if row.Phase == "FINISHED" || row.SimulationHash == stringValue(s.rules.Manifest["simulation_hash"]) || row.Lease.After(time.Now().Add(-30*time.Second)) {
				return nil
			}
			if err = s.finishMatch(s.ctx, tx, row, -1, "SERVER_ABORTED", row.Tick); err != nil {
				return err
			}
			_, err = tx.Exec(s.ctx, "UPDATE online_matches SET phase='FINISHED' WHERE id=$1", id)
			return err
		})
	}
}

func (s *Server) recordRecoveryFailure(id string) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = s.store.transaction(ctx, func(tx pgx.Tx) error {
		row, err := loadMatch(ctx, tx, id, true)
		if err != nil || row.Phase == "FINISHED" {
			return err
		}
		if row.Owner != "" && row.Owner != s.instance && row.Lease.After(time.Now()) {
			return nil
		}
		if row.Control.RecoveryStartedMS == 0 {
			row.Control.RecoveryStartedMS = nowMillis()
		}
		row.Control.Paused = true
		row.Control.PauseReason = "SERVER_RECOVERING"
		if nowMillis()-row.Control.RecoveryStartedMS >= 30000 {
			if err = s.finishMatch(ctx, tx, row, -1, "SERVER_ABORTED", row.Tick); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, "UPDATE online_matches SET phase=$2,control=$3 WHERE id=$1", id, row.Phase, encode(row.Control))
		return err
	})
}

func sortCommands(commands []Object, tick int64) {
	for i := 1; i < len(commands); i++ {
		for j := i; j > 0; j-- {
			a, b := commands[j-1], commands[j]
			less := number(a["apply_tick"]) > number(b["apply_tick"])
			if number(a["apply_tick"]) == number(b["apply_tick"]) {
				if a["player_id"] == b["player_id"] {
					less = number(a["client_seq"]) > number(b["client_seq"])
				} else {
					less = (number(a["side"])+tick/3)%2 > (number(b["side"])+tick/3)%2
				}
			}
			if !less {
				break
			}
			commands[j-1], commands[j] = commands[j], commands[j-1]
		}
	}
}
func (s *Server) persistBatch(ctx context.Context, tx pgx.Tx, row *MatchRow, response *WorkerResponse, requireOwner bool) error {
	compressed, err := compressSnapshot(response.Snapshot)
	if err != nil {
		return err
	}
	hash := digest(compressed)
	for _, result := range response.Results {
		status := "REJECTED"
		if boolValue(result.Result["ok"]) {
			status = "APPLIED"
		}
		result.Result["status"] = status
		result.Result["client_seq"] = result.Seq
		result.Result["applied_tick"] = result.Tick
		if _, err = tx.Exec(ctx, "UPDATE online_commands SET status=$4,result=$5 WHERE match_id=$1 AND player_id=$2 AND client_seq=$3 AND status='PENDING'", row.ID, result.PlayerID, result.Seq, status, encode(result.Result)); err != nil {
			return err
		}
	}
	row.Batch++
	if _, err = tx.Exec(ctx, "INSERT INTO online_batches(match_id,batch_seq,tick,owner_epoch,snapshot_hash) VALUES($1,$2,$3,$4,$5)", row.ID, row.Batch, response.Tick, row.OwnerEpoch, hash); err != nil {
		return err
	}
	expectedEpoch := row.OwnerEpoch
	if !requireOwner {
		expectedEpoch--
	}
	commandTag, err := tx.Exec(ctx, "UPDATE online_matches SET phase=$2,control=$3,snapshot=$4,snapshot_hash=$5,projections=$6,committed_tick=$7,batch_seq=$8,owner_id=$9,owner_epoch=$10,lease_until=clock_timestamp()+interval '6 seconds',updated_at=now() WHERE id=$1 AND batch_seq=$11 AND owner_epoch=$12 AND ($13=false OR owner_id=$9)", row.ID, row.Phase, encode(row.Control), compressed, hash, encode(response.Projections), response.Tick, row.Batch, row.Owner, row.OwnerEpoch, row.Batch-1, expectedEpoch, requireOwner)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return fmt.Errorf("commit fence mismatch")
	}
	return nil
}
func (s *Server) finishMatch(ctx context.Context, tx pgx.Tx, row *MatchRow, winner int, reason string, tick int64) error {
	_, err := tx.Exec(ctx, "INSERT INTO online_results(match_id,result_id,winner,reason,tick) VALUES($1,$2,$3,$4,$5) ON CONFLICT(match_id) DO NOTHING", row.ID, identifier(), winner, reason, tick)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, "INSERT INTO online_outbox(id,match_id,type,payload) VALUES($1,$2,'MATCH_RESULT',$3) ON CONFLICT(id) DO NOTHING", "result-"+row.ID, row.ID, encode(Object{"winner": winner, "reason": reason}))
	if err != nil {
		return err
	}
	row.Phase = "FINISHED"
	return closeRoom(ctx, tx, row.RoomID)
}
func (s *Server) matchResult(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, id string) (Object, error) {
	var result string
	var winner int
	var reason string
	var tick int64
	var created time.Time
	err := q.QueryRow(ctx, "SELECT result_id,winner,reason,tick,created_at FROM online_results WHERE match_id=$1", id).Scan(&result, &winner, &reason, &tick, &created)
	if err == pgx.ErrNoRows {
		return Object{"status": "PENDING"}, nil
	}
	if err != nil {
		return nil, err
	}
	return Object{"status": "FINISHED", "match_id": id, "result_id": result, "winner": winner, "reason": reason, "tick": tick, "created_at_ms": created.UnixMilli()}, nil
}
