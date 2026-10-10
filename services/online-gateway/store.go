package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrations embed.FS

type Store struct{ pool *pgxpool.Pool }

func openStore(ctx context.Context, url string) (*Store, error) {
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("invalid database configuration")
	}
	config.MaxConns = 24
	config.ConnConfig.ConnectTimeout = 5 * time.Second
	config.ConnConfig.RuntimeParams["synchronous_commit"] = "on"
	config.ConnConfig.RuntimeParams["statement_timeout"] = "5000"
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, err
	}
	if err = pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("database is unavailable")
	}
	data, _ := migrations.ReadFile("migrations/001_online.sql")
	if _, err = pool.Exec(ctx, string(data)); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}
func (s *Store) transaction(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err = fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func globalLobbyLock(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(840731)")
	return err
}
func bytesReader(b []byte) *bytes.Reader { return bytes.NewReader(b) }
func compressSnapshot(b []byte) ([]byte, error) {
	var buf bytes.Buffer
	w, _ := gzip.NewWriterLevel(&buf, gzip.BestSpeed)
	if _, err := w.Write(b); err != nil {
		return nil, err
	}
	if err := w.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
func restoreSnapshot(row *MatchRow) ([]byte, error) {
	if digest(row.Snapshot) != row.SnapshotHash {
		return nil, fmt.Errorf("checkpoint checksum mismatch")
	}
	r, err := gzip.NewReader(bytesReader(row.Snapshot))
	if err != nil {
		return nil, err
	}
	defer r.Close()
	b, err := io.ReadAll(io.LimitReader(r, 4194305))
	if err != nil || len(b) > 4194304 {
		return nil, fmt.Errorf("checkpoint exceeds limit")
	}
	return b, nil
}
func scanMatch(row pgx.Row) (*MatchRow, error) {
	r := &MatchRow{}
	var c, p []byte
	err := row.Scan(&r.ID, &r.RoomID, &r.Phase, &r.SimulationHash, &c, &r.Snapshot, &r.SnapshotHash, &p, &r.Tick, &r.Batch, &r.Owner, &r.OwnerEpoch, &r.Lease)
	if err != nil {
		return nil, err
	}
	if err = json.Unmarshal(c, &r.Control); err != nil {
		return nil, err
	}
	if err = json.Unmarshal(p, &r.Projections); err != nil {
		return nil, err
	}
	return r, nil
}

const matchColumns = "id,room_id,phase,simulation_hash,control,snapshot,snapshot_hash,projections,committed_tick,batch_seq,owner_id,owner_epoch,lease_until"

func loadMatch(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, id string, lock bool) (*MatchRow, error) {
	sql := "SELECT " + matchColumns + " FROM online_matches WHERE id=$1"
	if lock {
		sql += " FOR UPDATE"
	}
	return scanMatch(q.QueryRow(ctx, sql, id))
}
