package main

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5"
)

var roomCode = regexp.MustCompile(`^[0-9]{6}$`)

type Querier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

func (s *Server) activity(ctx context.Context, q Querier, player string) (Object, error) {
	var kind, id string
	var queued *time.Time
	if err := q.QueryRow(ctx, "SELECT activity_kind,activity_id,queued_at FROM online_players WHERE id=$1", player).Scan(&kind, &id, &queued); err != nil {
		return nil, err
	}
	activity := Object{"kind": kind, "id": id}
	if kind == "queue" {
		activity["wait_seconds"] = time.Since(*queued).Seconds()
		return activity, nil
	}
	if kind == "room" {
		room, err := s.room(ctx, q, id, player)
		if err != nil {
			return nil, err
		}
		activity["room"] = room
	}
	if kind == "match" {
		row, err := loadMatch(ctx, q, id, false)
		if err != nil {
			return nil, err
		}
		activity["seat"] = row.Control.seatFor(player)
		activity["phase"] = row.Phase
		if row.Phase == "FINISHED" {
			activity["result"], err = s.matchResult(ctx, q, id)
			if err != nil {
				return nil, err
			}
		}
	}
	return activity, nil
}
func (s *Server) activityHTTP(w http.ResponseWriter, r *http.Request, player string) {
	if _, err := s.store.pool.Exec(r.Context(), "UPDATE online_players SET last_seen=now() WHERE id=$1", player); err != nil {
		errorResponse(w, err)
		return
	}
	_, _ = s.store.pool.Exec(r.Context(), "UPDATE online_seats SET last_seen=now() WHERE player_id=$1 AND room_id IN(SELECT id FROM online_rooms WHERE closed_at IS NULL)", player)
	activity, err := s.activity(r.Context(), s.store.pool, player)
	if err != nil {
		errorResponse(w, err)
		return
	}
	respond(w, 200, Object{"ok": true, "activity": activity})
}
func (s *Server) room(ctx context.Context, q Querier, id, viewer string) (Object, error) {
	var code *string
	var phase string
	var revision int64
	var data []byte
	var expires time.Time
	if err := q.QueryRow(ctx, "SELECT code,phase,revision,data,expires_at FROM online_rooms WHERE id=$1", id).Scan(&code, &phase, &revision, &data, &expires); err != nil {
		return nil, err
	}
	var options Object
	_ = json.Unmarshal(data, &options)
	rows, err := q.Query(ctx, "SELECT seat,player_id,loadout,ready FROM online_seats WHERE room_id=$1 ORDER BY seat", id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	roster := []Object{}
	for rows.Next() {
		var seat int
		var player string
		var loadout []byte
		var ready bool
		if err = rows.Scan(&seat, &player, &loadout, &ready); err != nil {
			return nil, err
		}
		var build Object
		_ = json.Unmarshal(loadout, &build)
		roster = append(roster, Object{"seat": seat, "player_id": player, "is_you": player == viewer, "loadout": build, "ready": ready})
	}
	result := Object{"id": id, "code": "", "phase": phase, "revision": revision, "roster": roster, "expires_at_ms": expires.UnixMilli(), "region": "default", "ruleset_id": "pvp-classic-v1"}
	if code != nil {
		result["code"] = *code
	}
	return result, rows.Err()
}
func activeCheck(ctx context.Context, tx pgx.Tx, player string) (string, string, error) {
	var kind, id string
	err := tx.QueryRow(ctx, "SELECT activity_kind,activity_id FROM online_players WHERE id=$1 FOR UPDATE", player).Scan(&kind, &id)
	return kind, id, err
}

func (s *Server) joinCodeHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if s.draining.Load() {
			return nil, invalid("MAINTENANCE")
		}
		if err := s.rules.compatible(b); err != nil {
			return nil, err
		}
		code, ok := b["code"].(string)
		if !ok || !roomCode.MatchString(code) {
			return nil, failure("INVALID_ROOM_CODE", 400)
		}
		build, err := s.rules.loadout(b)
		if err != nil {
			return nil, err
		}
		if err = rateLimit(ctx, tx, player, "POST /v1/rooms/by-code", 10); err != nil {
			return nil, err
		}
		if err = globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		kind, active, err := activeCheck(ctx, tx, player)
		if err != nil {
			return nil, err
		}
		if kind != "" {
			activity, err := s.activity(ctx, tx, player)
			return Object{"ok": true, "status": "ALREADY_ACTIVE", "activity": activity}, err
		}
		var id string
		var data []byte
		var phase string
		err = tx.QueryRow(ctx, "SELECT id,data,phase FROM online_rooms WHERE code=$1 AND closed_at IS NULL FOR UPDATE", code).Scan(&id, &data, &phase)
		status := "JOINED"
		seat := 0
		if err == pgx.ErrNoRows {
			var cooling bool
			if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM online_code_cooldowns WHERE code=$1 AND until_at>now())", code).Scan(&cooling); err != nil {
				return nil, err
			}
			if cooling {
				return nil, invalid("CODE_COOLDOWN")
			}
			if err = rateLimit(ctx, tx, player, "CREATE_ROOM", 5); err != nil {
				return nil, err
			}
			id = identifier()
			status = "CREATED"
			_, err = tx.Exec(ctx, "INSERT INTO online_rooms(id,code,data,expires_at) VALUES($1,$2,$3,now()+interval '300 seconds')", id, code, encode(Object{"simulation_hash": s.rules.Manifest["simulation_hash"]}))
			if err != nil {
				return nil, err
			}
			_, err = tx.Exec(ctx, "INSERT INTO online_requests(player_id,request_id,endpoint,payload_hash,response) VALUES($1,$2,'CREATE_ROOM','', '{}')", player, identifier())
			if err != nil {
				return nil, err
			}
		} else if err != nil {
			return nil, err
		} else {
			var options Object
			_ = json.Unmarshal(data, &options)
			if options["simulation_hash"] != s.rules.Manifest["simulation_hash"] {
				return nil, failure("VERSION_MISMATCH", 426)
			}
			if phase != "WAITING" {
				return nil, invalid("ROOM_FULL")
			}
			var occupied []int
			rows, err := tx.Query(ctx, "SELECT seat FROM online_seats WHERE room_id=$1", id)
			if err != nil {
				return nil, err
			}
			for rows.Next() {
				var index int
				_ = rows.Scan(&index)
				occupied = append(occupied, index)
			}
			rows.Close()
			if len(occupied) >= 2 {
				return nil, invalid("ROOM_FULL")
			}
			if len(occupied) > 0 && occupied[0] == 0 {
				seat = 1
			}
			_, err = tx.Exec(ctx, "UPDATE online_rooms SET revision=revision+1,expires_at=LEAST(created_at+interval '600 seconds',now()+interval '300 seconds') WHERE id=$1", id)
			if err != nil {
				return nil, err
			}
			_, err = tx.Exec(ctx, "UPDATE online_seats SET ready=false WHERE room_id=$1", id)
			if err != nil {
				return nil, err
			}
		}
		_, err = tx.Exec(ctx, "INSERT INTO online_seats(room_id,seat,player_id,loadout) VALUES($1,$2,$3,$4)", id, seat, player, encode(build))
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, "UPDATE online_players SET activity_kind='room',activity_id=$2 WHERE id=$1", player, id)
		if err != nil {
			return nil, err
		}
		_ = active
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "status": status, "activity": activity}, err
	})
}

func (s *Server) queueHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if s.draining.Load() {
			return nil, invalid("MAINTENANCE")
		}
		if err := s.rules.compatible(b); err != nil {
			return nil, err
		}
		build, err := s.rules.loadout(b)
		if err != nil {
			return nil, err
		}
		if err = globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		kind, _, err := activeCheck(ctx, tx, player)
		if err != nil {
			return nil, err
		}
		if kind == "" {
			_, err = tx.Exec(ctx, "UPDATE online_players SET activity_kind='queue',activity_id=$2,queued_at=now(),last_seen=now(),loadout=$3,simulation_hash=$4 WHERE id=$1", player, identifier(), encode(build), s.rules.Manifest["simulation_hash"])
			if err != nil {
				return nil, err
			}
		}
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "activity": activity}, err
	})
}
func (s *Server) cancelQueueHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if err := globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		_, err := tx.Exec(ctx, "UPDATE online_players SET activity_kind='',activity_id='',queued_at=NULL WHERE id=$1 AND activity_kind='queue' AND activity_id=$2", player, r.PathValue("id"))
		if err != nil {
			return nil, err
		}
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "activity": activity}, err
	})
}
func validateRoom(ctx context.Context, tx pgx.Tx, room, player string, b Object) (string, error) {
	var phase string
	var revision int64
	err := tx.QueryRow(ctx, "SELECT phase,revision FROM online_rooms WHERE id=$1 AND closed_at IS NULL FOR UPDATE", room).Scan(&phase, &revision)
	if err == pgx.ErrNoRows {
		return "", failure("ROOM_NOT_FOUND", 404)
	}
	if err != nil {
		return "", err
	}
	var member bool
	if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM online_seats WHERE room_id=$1 AND player_id=$2)", room, player).Scan(&member); err != nil {
		return "", err
	}
	if !member {
		return "", failure("NOT_MEMBER", 403)
	}
	if number(b["expected_revision"]) != revision {
		return "", invalid("ROOM_REVISION_CHANGED")
	}
	return phase, nil
}
func (s *Server) readyHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if err := globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		id := r.PathValue("id")
		phase, err := validateRoom(ctx, tx, id, player, b)
		if err != nil {
			return nil, err
		}
		if phase != "WAITING" {
			return nil, invalid("ROOM_NOT_WAITING")
		}
		ready, ok := b["ready"].(bool)
		if !ok {
			return nil, failure("INVALID_READY", 400)
		}
		_, err = tx.Exec(ctx, "UPDATE online_seats SET ready=$3,last_seen=now() WHERE room_id=$1 AND player_id=$2", id, player, ready)
		if err != nil {
			return nil, err
		}
		if err = s.maybeStart(ctx, tx, id); err != nil {
			return nil, err
		}
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "activity": activity}, err
	})
}
func (s *Server) loadoutHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		build, err := s.rules.loadout(b)
		if err != nil {
			return nil, err
		}
		if err = globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		id := r.PathValue("id")
		phase, err := validateRoom(ctx, tx, id, player, b)
		if err != nil {
			return nil, err
		}
		if phase != "WAITING" {
			return nil, invalid("ROOM_NOT_WAITING")
		}
		_, err = tx.Exec(ctx, "UPDATE online_seats SET loadout=$3 WHERE room_id=$1 AND player_id=$2", id, player, encode(build))
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, "UPDATE online_seats SET ready=false WHERE room_id=$1", id)
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, "UPDATE online_rooms SET revision=revision+1 WHERE id=$1", id)
		if err != nil {
			return nil, err
		}
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "activity": activity}, err
	})
}
func closeRoom(ctx context.Context, tx pgx.Tx, id string) error {
	var code *string
	if err := tx.QueryRow(ctx, "UPDATE online_rooms SET closed_at=now(),phase='CLOSED' WHERE id=$1 AND closed_at IS NULL RETURNING code", id).Scan(&code); err != nil {
		if err == pgx.ErrNoRows {
			return nil
		}
		return err
	}
	if code != nil {
		if _, err := tx.Exec(ctx, "INSERT INTO online_code_cooldowns(code,until_at) VALUES($1,now()+interval '90 seconds') ON CONFLICT(code) DO UPDATE SET until_at=excluded.until_at", *code); err != nil {
			return err
		}
	}
	_, err := tx.Exec(ctx, "UPDATE online_players SET activity_kind='',activity_id='' WHERE activity_kind='room' AND activity_id=$1", id)
	return err
}
func (s *Server) leaveRoomHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if err := globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		id := r.PathValue("id")
		kind, active, err := activeCheck(ctx, tx, player)
		if err != nil {
			return nil, err
		}
		if kind == "match" {
			return nil, invalid("SURRENDER_REQUIRED")
		}
		if kind != "room" || active != id {
			return Object{"ok": true}, nil
		}
		var phase string
		if err = tx.QueryRow(ctx, "SELECT phase FROM online_rooms WHERE id=$1 FOR UPDATE", id).Scan(&phase); err != nil {
			return nil, err
		}
		if phase == "OFFER" {
			err = closeRoom(ctx, tx, id)
		} else {
			_, err = tx.Exec(ctx, "DELETE FROM online_seats WHERE room_id=$1 AND player_id=$2", id, player)
			if err != nil {
				return nil, err
			}
			_, err = tx.Exec(ctx, "UPDATE online_players SET activity_kind='',activity_id='' WHERE id=$1", player)
			if err != nil {
				return nil, err
			}
			var count int
			if err = tx.QueryRow(ctx, "SELECT count(*) FROM online_seats WHERE room_id=$1", id).Scan(&count); err != nil {
				return nil, err
			}
			if count == 0 {
				err = closeRoom(ctx, tx, id)
			} else {
				_, err = tx.Exec(ctx, "UPDATE online_rooms SET revision=revision+1 WHERE id=$1", id)
				if err == nil {
					_, err = tx.Exec(ctx, "UPDATE online_seats SET ready=false WHERE room_id=$1", id)
				}
			}
		}
		return Object{"ok": true, "activity": Object{"kind": "", "id": ""}}, err
	})
}
func (s *Server) offerHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		ctx := r.Context()
		if err := globalLobbyLock(ctx, tx); err != nil {
			return nil, err
		}
		id := r.PathValue("id")
		b["expected_revision"] = b["offer_revision"]
		phase, err := validateRoom(ctx, tx, id, player, b)
		if err != nil {
			return nil, err
		}
		if phase != "OFFER" {
			return nil, invalid("OFFER_EXPIRED")
		}
		if !boolValue(b["accept"]) {
			return Object{"ok": true}, closeRoom(ctx, tx, id)
		}
		_, err = tx.Exec(ctx, "UPDATE online_seats SET ready=true,last_seen=now() WHERE room_id=$1 AND player_id=$2", id, player)
		if err != nil {
			return nil, err
		}
		if err = s.maybeStart(ctx, tx, id); err != nil {
			return nil, err
		}
		activity, err := s.activity(ctx, tx, player)
		return Object{"ok": true, "activity": activity}, err
	})
}
func (s *Server) maybeStart(ctx context.Context, tx pgx.Tx, roomID string) error {
	rows, err := tx.Query(ctx, "SELECT player_id,loadout,ready FROM online_seats WHERE room_id=$1 ORDER BY seat", roomID)
	if err != nil {
		return err
	}
	control := MatchControl{Seed: time.Now().UnixNano() % 2147483647, LoadingDeadlineMS: nowMillis() + 30000, LastAccountedMS: nowMillis()}
	allReady := true
	for rows.Next() {
		var player string
		var raw []byte
		var ready bool
		if err = rows.Scan(&player, &raw, &ready); err != nil {
			rows.Close()
			return err
		}
		var build Object
		_ = json.Unmarshal(raw, &build)
		control.Seats = append(control.Seats, SeatControl{PlayerID: player, Loadout: build, NextSeq: 1, LastSeenMS: nowMillis()})
		allReady = allReady && ready
	}
	rows.Close()
	if len(control.Seats) != 2 || !allReady {
		return nil
	}
	if s.draining.Load() {
		return failure("MAINTENANCE", 503)
	}
	var count int
	if err = tx.QueryRow(ctx, "SELECT count(*) FROM online_matches WHERE phase!='FINISHED'").Scan(&count); err != nil {
		return err
	}
	if count >= s.maxMatches {
		return invalid("SERVER_FULL")
	}
	id := identifier()
	_, err = tx.Exec(ctx, "INSERT INTO online_matches(id,room_id,simulation_hash,control) VALUES($1,$2,$3,$4)", id, roomID, s.rules.Manifest["simulation_hash"], encode(control))
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, "UPDATE online_rooms SET phase='LOADING' WHERE id=$1", roomID)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, "UPDATE online_players SET activity_kind='match',activity_id=$2 WHERE id=ANY($1)", []string{control.Seats[0].PlayerID, control.Seats[1].PlayerID}, id)
	return err
}

func (s *Server) lobbyMaintenance() {
	timer := time.NewTicker(500 * time.Millisecond)
	defer timer.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-timer.C:
			_ = s.store.transaction(s.ctx, func(tx pgx.Tx) error {
				if err := globalLobbyLock(s.ctx, tx); err != nil {
					return err
				}
				rows, err := tx.Query(s.ctx, "SELECT id FROM online_rooms WHERE closed_at IS NULL AND phase IN ('WAITING','OFFER') AND (expires_at<now() OR created_at<now()-interval '600 seconds') FOR UPDATE")
				if err != nil {
					return err
				}
				var expired []string
				for rows.Next() {
					var id string
					_ = rows.Scan(&id)
					expired = append(expired, id)
				}
				rows.Close()
				for _, id := range expired {
					if err = closeRoom(s.ctx, tx, id); err != nil {
						return err
					}
				}
				rows, err = tx.Query(s.ctx, "SELECT room_id,player_id FROM online_seats WHERE last_seen<now()-interval '60 seconds' AND room_id IN(SELECT id FROM online_rooms WHERE closed_at IS NULL AND phase='WAITING')")
				if err != nil {
					return err
				}
				type staleSeat struct{ room, player string }
				var stale []staleSeat
				for rows.Next() {
					var seat staleSeat
					_ = rows.Scan(&seat.room, &seat.player)
					stale = append(stale, seat)
				}
				rows.Close()
				for _, seat := range stale {
					if _, err = tx.Exec(s.ctx, "DELETE FROM online_seats WHERE room_id=$1 AND player_id=$2", seat.room, seat.player); err != nil {
						return err
					}
					_, _ = tx.Exec(s.ctx, "UPDATE online_players SET activity_kind='',activity_id='' WHERE id=$1 AND activity_id=$2", seat.player, seat.room)
					_, _ = tx.Exec(s.ctx, "UPDATE online_rooms SET revision=revision+1 WHERE id=$1", seat.room)
					_, _ = tx.Exec(s.ctx, "UPDATE online_seats SET ready=false WHERE room_id=$1", seat.room)
				}
				if s.draining.Load() {
					return nil
				}
				if _, err = tx.Exec(s.ctx, "UPDATE online_players SET activity_kind='',activity_id='',queued_at=NULL WHERE activity_kind='queue' AND last_seen<now()-interval '60 seconds'"); err != nil {
					return err
				}
				return s.matchmake(s.ctx, tx)
			})
		}
	}
}
func (s *Server) matchmake(ctx context.Context, tx pgx.Tx) error {
	rows, err := tx.Query(ctx, "SELECT id,loadout,skill,queued_at FROM online_players WHERE activity_kind='queue' AND simulation_hash=$1 ORDER BY queued_at LIMIT 100 FOR UPDATE", s.rules.Manifest["simulation_hash"])
	if err != nil {
		return err
	}
	type candidate struct {
		id      string
		loadout []byte
		skill   int
		queued  time.Time
	}
	var players []candidate
	for rows.Next() {
		var p candidate
		if err = rows.Scan(&p.id, &p.loadout, &p.skill, &p.queued); err != nil {
			rows.Close()
			return err
		}
		players = append(players, p)
	}
	rows.Close()
	used := map[string]bool{}
	for i, p := range players {
		if used[p.id] {
			continue
		}
		for _, other := range players[i+1:] {
			if used[other.id] {
				continue
			}
			window := 150
			if time.Since(p.queued) >= 20*time.Second {
				window = 300
			}
			if time.Since(p.queued) >= 40*time.Second {
				window = 500
			}
			difference := p.skill - other.skill
			if difference < 0 {
				difference = -difference
			}
			if difference > window {
				continue
			}
			id := identifier()
			_, err = tx.Exec(ctx, "INSERT INTO online_rooms(id,phase,data,expires_at) VALUES($1,'OFFER',$2,now()+interval '15 seconds')", id, encode(Object{"simulation_hash": s.rules.Manifest["simulation_hash"], "matched": true}))
			if err != nil {
				return err
			}
			for seat, c := range []candidate{p, other} {
				if _, err = tx.Exec(ctx, "INSERT INTO online_seats(room_id,seat,player_id,loadout) VALUES($1,$2,$3,$4)", id, seat, c.id, c.loadout); err != nil {
					return err
				}
				if _, err = tx.Exec(ctx, "UPDATE online_players SET activity_kind='room',activity_id=$2 WHERE id=$1", c.id, id); err != nil {
					return err
				}
			}
			used[p.id] = true
			used[other.id] = true
			break
		}
	}
	return nil
}
