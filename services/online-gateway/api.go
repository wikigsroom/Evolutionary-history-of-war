package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

func respond(w http.ResponseWriter, code int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(data)
}
func errorResponse(w http.ResponseWriter, err error) {
	status := 503
	var api *APIError
	if errors.As(err, &api) {
		status = api.Status
	}
	if status == 429 {
		w.Header().Set("Retry-After", "10")
	}
	respond(w, status, describeError(err))
}
func bodyOf(w http.ResponseWriter, r *http.Request) (Object, error) {
	b, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 8192))
	if err != nil {
		return nil, failure("MESSAGE_TOO_LARGE", 413)
	}
	var result Object
	if err = json.Unmarshal(b, &result); err != nil || result == nil {
		return nil, failure("INVALID_JSON", 400)
	}
	return result, nil
}
func (s *Server) authenticate(ctx context.Context, r *http.Request) (string, error) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if len(token) != 64 {
		return "", failure("UNAUTHORIZED", 401)
	}
	var id string
	err := s.store.pool.QueryRow(ctx, "SELECT player_id FROM online_tokens WHERE hash=$1 AND expires_at>now()", digest([]byte(token))).Scan(&id)
	if err == pgx.ErrNoRows {
		return "", failure("UNAUTHORIZED", 401)
	}
	return id, err
}
func (s *Server) authed(fn func(http.ResponseWriter, *http.Request, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := s.authenticate(r.Context(), r)
		if err != nil {
			errorResponse(w, err)
			return
		}
		fn(w, r, id)
	}
}
func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		ctx, c := context.WithTimeout(r.Context(), time.Second)
		defer c()
		if s.store.pool.Ping(ctx) != nil {
			respond(w, 503, Object{"ok": false})
			return
		}
		var active int
		draining := s.draining.Load()
		err := s.store.transaction(ctx, func(tx pgx.Tx) error {
			// When draining, wait for any admission transaction that observed the
			// old flag. A zero count must include every previously accepted match.
			if draining {
				if err := globalLobbyLock(ctx, tx); err != nil {
					return err
				}
			}
			return tx.QueryRow(ctx, "SELECT count(*) FROM online_matches WHERE phase!='FINISHED'").Scan(&active)
		})
		if err != nil {
			respond(w, 503, Object{"ok": false})
			return
		}
		respond(w, 200, Object{"ok": true, "service": "epoch-rush-online", "draining": draining, "active_matches": active, "max_matches": s.maxMatches})
	})
	mux.HandleFunc("GET /v1/bootstrap", func(w http.ResponseWriter, r *http.Request) {
		respond(w, 200, Object{"ok": true, "protocol_version": "1.0", "simulation_hash": s.rules.Manifest["simulation_hash"], "ruleset_id": "pvp-classic-v1", "ruleset_hash": s.rules.Manifest["ruleset_hash"], "region": "default", "online_enabled": !s.draining.Load(), "heartbeat_seconds": 2, "match_capacity": s.maxMatches})
	})
	mux.HandleFunc("POST /v1/auth/guest", s.guest)
	mux.HandleFunc("POST /v1/auth/refresh", s.guest)
	mux.HandleFunc("GET /v1/activities/me", s.authed(s.activityHTTP))
	mux.HandleFunc("POST /v1/rooms/by-code", s.authed(s.joinCodeHTTP))
	mux.HandleFunc("POST /v1/rooms/{id}/ready", s.authed(s.readyHTTP))
	mux.HandleFunc("PATCH /v1/rooms/{id}/loadout", s.authed(s.loadoutHTTP))
	mux.HandleFunc("POST /v1/rooms/{id}/leave", s.authed(s.leaveRoomHTTP))
	mux.HandleFunc("POST /v1/matchmaking/tickets", s.authed(s.queueHTTP))
	mux.HandleFunc("DELETE /v1/matchmaking/tickets/{id}", s.authed(s.cancelQueueHTTP))
	mux.HandleFunc("POST /v1/match-offers/{id}/decision", s.authed(s.offerHTTP))
	mux.HandleFunc("POST /v1/ws-tickets", s.authed(s.ticketHTTP))
	mux.HandleFunc("POST /v1/matches/{id}/surrender", s.authed(s.surrenderHTTP))
	mux.HandleFunc("GET /v1/matches/{id}/result", s.authed(s.resultHTTP))
	mux.HandleFunc("POST /v1/matches/{id}/ack-result", s.authed(s.ackResultHTTP))
	mux.HandleFunc("GET /v1/socket", s.socketHTTP)
	return mux
}

func (s *Server) guest(w http.ResponseWriter, r *http.Request) {
	body, err := bodyOf(w, r)
	if err != nil {
		errorResponse(w, err)
		return
	}
	key, err := requireString(body, "installation_key", 64, 64)
	if err != nil {
		errorResponse(w, err)
		return
	}
	if _, err = hex.DecodeString(key); err != nil {
		errorResponse(w, failure("INVALID_CREDENTIAL", 400))
		return
	}
	// Installation keys are generated with a CSPRNG by the client. No hardware IDs.
	var id string
	access := secret()
	err = s.store.transaction(r.Context(), func(tx pgx.Tx) error {
		err := tx.QueryRow(r.Context(), "INSERT INTO online_players(id,credential_hash) VALUES($1,$2) ON CONFLICT(credential_hash) DO UPDATE SET last_seen=now() RETURNING id", identifier(), digest([]byte(key))).Scan(&id)
		if err != nil {
			return err
		}
		_, err = tx.Exec(r.Context(), "INSERT INTO online_tokens(hash,player_id,expires_at) VALUES($1,$2,now()+interval '15 minutes')", digest([]byte(access)), id)
		return err
	})
	if err != nil {
		errorResponse(w, err)
		return
	}
	respond(w, 200, Object{"ok": true, "player_id": id, "access_token": access, "expires_in": 900})
}

func (s *Server) mutate(w http.ResponseWriter, r *http.Request, player string, fn func(pgx.Tx, Object) (Object, error)) {
	body, err := bodyOf(w, r)
	if err != nil {
		errorResponse(w, err)
		return
	}
	id, err := requireString(body, "request_id", 16, 64)
	if err != nil {
		errorResponse(w, err)
		return
	}
	hash := digest(encode(body))
	endpoint := r.Method + " " + r.URL.Path
	var response Object
	status := 200
	err = s.store.transaction(r.Context(), func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(), "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", player); err != nil {
			return err
		}
		var oldHash, oldEndpoint string
		var raw []byte
		err := tx.QueryRow(r.Context(), "SELECT payload_hash,endpoint,response FROM online_requests WHERE player_id=$1 AND request_id=$2", player, id).Scan(&oldHash, &oldEndpoint, &raw)
		if err == nil {
			if oldHash != hash || oldEndpoint != endpoint {
				return invalid("IDEMPOTENCY_CONFLICT")
			}
			_ = json.Unmarshal(raw, &response)
			status = int(number(response["http_status"]))
			if status == 0 {
				status = 200
			}
			return nil
		}
		if err != pgx.ErrNoRows {
			return err
		}
		if _, err = tx.Exec(r.Context(), "SAVEPOINT business"); err != nil {
			return err
		}
		response, err = fn(tx, body)
		if err != nil {
			var api *APIError
			if !errors.As(err, &api) {
				return err
			}
			if _, rollbackErr := tx.Exec(r.Context(), "ROLLBACK TO SAVEPOINT business"); rollbackErr != nil {
				return rollbackErr
			}
			response = describeError(api)
			status = api.Status
		}
		response["http_status"] = status
		_, err = tx.Exec(r.Context(), "INSERT INTO online_requests(player_id,request_id,endpoint,payload_hash,response) VALUES($1,$2,$3,$4,$5)", player, id, endpoint, hash, encode(response))
		return err
	})
	if err != nil {
		errorResponse(w, err)
		return
	}
	if status == 429 {
		w.Header().Set("Retry-After", "10")
	}
	respond(w, status, response)
}

func rateLimit(ctx context.Context, tx pgx.Tx, player, endpoint string, limit int) error {
	var count int
	err := tx.QueryRow(ctx, "SELECT count(*) FROM online_requests WHERE player_id=$1 AND endpoint=$2 AND created_at>now()-interval '1 minute'", player, endpoint).Scan(&count)
	if err != nil {
		return err
	}
	if count >= limit {
		return failure("RATE_LIMITED", 429)
	}
	return nil
}

func (s *Server) resultHTTP(w http.ResponseWriter, r *http.Request, player string) {
	row, err := loadMatch(r.Context(), s.store.pool, r.PathValue("id"), false)
	if err != nil {
		errorResponse(w, failure("MATCH_NOT_FOUND", 404))
		return
	}
	if row.Control.seatFor(player) < 0 {
		errorResponse(w, failure("NOT_MEMBER", 403))
		return
	}
	result, err := s.matchResult(r.Context(), s.store.pool, row.ID)
	if err != nil {
		errorResponse(w, err)
		return
	}
	respond(w, 200, Object{"ok": true, "result": result})
}
func (s *Server) ackResultHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		row, err := loadMatch(r.Context(), tx, r.PathValue("id"), true)
		if err != nil {
			return nil, err
		}
		if row.Control.seatFor(player) < 0 {
			return nil, failure("NOT_MEMBER", 403)
		}
		if row.Phase != "FINISHED" {
			return nil, invalid("MATCH_ACTIVE")
		}
		_, err = tx.Exec(r.Context(), "UPDATE online_players SET activity_kind='',activity_id='' WHERE id=$1 AND activity_id=$2", player, row.ID)
		return Object{"ok": true}, err
	})
}

func (s *Server) surrenderHTTP(w http.ResponseWriter, r *http.Request, player string) {
	s.mutate(w, r, player, func(tx pgx.Tx, b Object) (Object, error) {
		if !boolValue(b["confirm"]) {
			return nil, failure("CONFIRM_REQUIRED", 400)
		}
		row, err := loadMatch(r.Context(), tx, r.PathValue("id"), true)
		if err != nil {
			return nil, err
		}
		seat := row.Control.seatFor(player)
		if seat < 0 {
			return nil, failure("NOT_MEMBER", 403)
		}
		if row.Phase != "FINISHED" {
			row.Control.Seats[seat].Surrender = true
			_, err = tx.Exec(r.Context(), "UPDATE online_matches SET control=$2 WHERE id=$1", row.ID, encode(row.Control))
		}
		return Object{"ok": true, "status": "SUBMITTED"}, err
	})
}
