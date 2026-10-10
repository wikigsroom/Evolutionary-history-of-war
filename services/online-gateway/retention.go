package main

import (
	"github.com/jackc/pgx/v5"
	"time"
)

// Bounded native maintenance; never deletes an active match or its deduplication ledger.
func (s *Server) retentionLoop() {
	timer := time.NewTicker(time.Minute)
	defer timer.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-timer.C:
			for _, query := range []string{
				"DELETE FROM online_tokens WHERE hash IN(SELECT hash FROM online_tokens WHERE expires_at<now() LIMIT 10000)",
				"DELETE FROM online_ws_tickets WHERE hash IN(SELECT hash FROM online_ws_tickets WHERE expires_at<now() LIMIT 10000)",
				"DELETE FROM online_code_cooldowns WHERE until_at<now()",
				"DELETE FROM online_requests WHERE (player_id,request_id) IN(SELECT player_id,request_id FROM online_requests WHERE created_at<now()-interval '24 hours' LIMIT 10000)",
			} {
				_, _ = s.store.pool.Exec(s.ctx, query)
			}
			rows, err := s.store.pool.Query(s.ctx, "SELECT id FROM online_matches WHERE phase='FINISHED' AND updated_at<now()-interval '30 days' LIMIT 20")
			if err != nil {
				continue
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
					if row.Phase != "FINISHED" {
						return nil
					}
					for _, table := range []string{"online_commands", "online_batches", "online_results", "online_outbox"} {
						if _, err = tx.Exec(s.ctx, "DELETE FROM "+table+" WHERE match_id=$1", id); err != nil {
							return err
						}
					}
					if _, err = tx.Exec(s.ctx, "UPDATE online_players SET activity_kind='',activity_id='' WHERE activity_kind='match' AND activity_id=$1", id); err != nil {
						return err
					}
					if _, err = tx.Exec(s.ctx, "DELETE FROM online_matches WHERE id=$1", id); err != nil {
						return err
					}
					if _, err = tx.Exec(s.ctx, "DELETE FROM online_seats WHERE room_id=$1", row.RoomID); err != nil {
						return err
					}
					_, err = tx.Exec(s.ctx, "DELETE FROM online_rooms WHERE id=$1", row.RoomID)
					return err
				})
			}
			_ = s.store.transaction(s.ctx, func(tx pgx.Tx) error {
				_, err := tx.Exec(s.ctx, `DELETE FROM online_seats WHERE room_id IN (
                    SELECT id FROM online_rooms r WHERE closed_at<now()-interval '30 days'
                    AND NOT EXISTS(SELECT 1 FROM online_matches m WHERE m.room_id=r.id) LIMIT 100)`)
				if err != nil {
					return err
				}
				_, err = tx.Exec(s.ctx, "DELETE FROM online_rooms WHERE closed_at<now()-interval '30 days' AND NOT EXISTS(SELECT 1 FROM online_matches m WHERE m.room_id=online_rooms.id) AND NOT EXISTS(SELECT 1 FROM online_seats t WHERE t.room_id=online_rooms.id)")
				if err != nil {
					return err
				}
				_, err = tx.Exec(s.ctx, `DELETE FROM online_players WHERE activity_kind='' AND last_seen<now()-interval '90 days'
                    AND NOT EXISTS(SELECT 1 FROM online_commands c WHERE c.player_id=online_players.id)
                    AND NOT EXISTS(SELECT 1 FROM online_seats t WHERE t.player_id=online_players.id)
                    AND NOT EXISTS(SELECT 1 FROM online_tokens t WHERE t.player_id=online_players.id)
                    AND NOT EXISTS(SELECT 1 FROM online_requests r WHERE r.player_id=online_players.id)`)
				return err
			})
		}
	}
}
