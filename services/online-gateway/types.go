package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

type Object = map[string]any

func identifier() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
func secret() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
func digest(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func encode(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}
func number(v any) int64 {
	switch n := v.(type) {
	case float64:
		return int64(n)
	case int:
		return int64(n)
	case int64:
		return n
	case json.Number:
		i, _ := n.Int64()
		return i
	}
	return 0
}
func stringValue(v any) string { s, _ := v.(string); return s }
func object(v any) Object {
	o, _ := v.(map[string]any)
	if o == nil {
		return Object{}
	}
	return o
}
func boolValue(v any) bool { b, _ := v.(bool); return b }
func nowMillis() int64     { return time.Now().UnixMilli() }

type APIError struct {
	Code   string
	Status int
}

func (e *APIError) Error() string           { return e.Code }
func failure(code string, status int) error { return &APIError{Code: code, Status: status} }
func invalid(code string) error             { return failure(code, 409) }

type SeatControl struct {
	PlayerID       string `json:"player_id"`
	Loadout        Object `json:"loadout"`
	Epoch          int64  `json:"connection_epoch"`
	GatewayID      string `json:"gateway_id"`
	Connected      bool   `json:"connected"`
	Loaded         bool   `json:"loaded"`
	LastSeenMS     int64  `json:"last_seen_ms"`
	OfflineSinceMS int64  `json:"offline_since_ms"`
	OfflineTotalMS int64  `json:"offline_total_ms"`
	PauseUsedMS    int64  `json:"pause_used_ms"`
	PauseUntilMS   int64  `json:"pause_until_ms"`
	NextSeq        int64  `json:"next_client_seq"`
	Surrender      bool   `json:"surrender"`
}
type MatchControl struct {
	Seats              []SeatControl `json:"seats"`
	Seed               int64         `json:"seed"`
	LoadingDeadlineMS  int64         `json:"loading_deadline_ms"`
	BothOfflineSinceMS int64         `json:"both_offline_since_ms"`
	LastAccountedMS    int64         `json:"last_accounted_ms"`
	Paused             bool          `json:"paused"`
	PauseReason        string        `json:"pause_reason"`
	RecoveryStartedMS  int64         `json:"recovery_started_ms"`
	PlatformSinceMS    int64         `json:"platform_since_ms"`
}

func (c *MatchControl) seatFor(player string) int {
	for i, s := range c.Seats {
		if s.PlayerID == player {
			return i
		}
	}
	return -1
}

type MatchRow struct {
	ID, RoomID, Phase, SimulationHash, SnapshotHash, Owner string
	Control                                                MatchControl
	Snapshot                                               []byte
	Projections                                            []Object
	Tick, Batch, OwnerEpoch                                int64
	Lease                                                  time.Time
}

type WorkerResponse struct {
	Error    string          `json:"error"`
	Detail   string          `json:"detail"`
	Snapshot json.RawMessage `json:"snapshot"`
	Tick     int64           `json:"tick"`
	Winner   int             `json:"winner"`
	Results  []struct {
		PlayerID string `json:"player_id"`
		Seq      int64  `json:"client_seq"`
		Result   Object `json:"result"`
		Tick     int64  `json:"tick"`
	} `json:"results"`
	Projections []Object `json:"projections"`
}

func requireString(o Object, key string, min, max int) (string, error) {
	s, ok := o[key].(string)
	if !ok || len(s) < min || len(s) > max {
		return "", failure("INVALID_"+key, 400)
	}
	return s, nil
}
func integer(o Object, key string, min, max int64) (int64, error) {
	v, ok := o[key].(float64)
	if !ok || v != float64(int64(v)) || int64(v) < min || int64(v) > max {
		return 0, failure("INVALID_"+key, 400)
	}
	return int64(v), nil
}
func describeError(err error) Object {
	if e, ok := err.(*APIError); ok {
		return Object{"ok": false, "error": e.Code}
	}
	return Object{"ok": false, "error": "SERVER_UNAVAILABLE"}
}
func exactPayload(o Object) (Object, error) {
	if o == nil {
		return nil, fmt.Errorf("missing object")
	}
	return o, nil
}
