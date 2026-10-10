-- Durable authority. All state-changing transactions use synchronous_commit=on.
CREATE TABLE IF NOT EXISTS online_players (
  id text PRIMARY KEY, credential_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(), activity_kind text NOT NULL DEFAULT '',
  activity_id text NOT NULL DEFAULT '', queued_at timestamptz,
  loadout jsonb NOT NULL DEFAULT '{}', simulation_hash text NOT NULL DEFAULT '', skill integer NOT NULL DEFAULT 1000,
  last_seen timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS online_tokens (
  hash text PRIMARY KEY, player_id text NOT NULL REFERENCES online_players(id),
  expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS online_requests (
  player_id text NOT NULL REFERENCES online_players(id), request_id text NOT NULL,
  endpoint text NOT NULL, payload_hash text NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(player_id, request_id)
);
CREATE TABLE IF NOT EXISTS online_gateways (
  id text PRIMARY KEY, last_seen timestamptz NOT NULL DEFAULT now(), draining boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS online_rooms (
  id text PRIMARY KEY, code text, phase text NOT NULL DEFAULT 'WAITING',
  revision bigint NOT NULL DEFAULT 1, data jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  closed_at timestamptz,
  CHECK (code IS NULL OR code ~ '^[0-9]{6}$')
);
CREATE UNIQUE INDEX IF NOT EXISTS online_active_code ON online_rooms(code) WHERE closed_at IS NULL;
CREATE TABLE IF NOT EXISTS online_seats (
  room_id text NOT NULL REFERENCES online_rooms(id), seat integer NOT NULL CHECK(seat IN (0,1)),
  player_id text NOT NULL REFERENCES online_players(id), loadout jsonb NOT NULL,
  ready boolean NOT NULL DEFAULT false, last_seen timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,seat), UNIQUE(room_id,player_id)
);
CREATE TABLE IF NOT EXISTS online_code_cooldowns (code text PRIMARY KEY, until_at timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS online_ws_tickets (
  hash text PRIMARY KEY, player_id text NOT NULL REFERENCES online_players(id), match_id text NOT NULL,
  expires_at timestamptz NOT NULL, consumed boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS online_matches (
  id text PRIMARY KEY, room_id text NOT NULL UNIQUE REFERENCES online_rooms(id),
  phase text NOT NULL DEFAULT 'LOADING', simulation_hash text NOT NULL,
  control jsonb NOT NULL, snapshot bytea, snapshot_hash text NOT NULL DEFAULT '',
  projections jsonb NOT NULL DEFAULT '[]', committed_tick bigint NOT NULL DEFAULT 0,
  batch_seq bigint NOT NULL DEFAULT 0, owner_id text NOT NULL DEFAULT '', owner_epoch bigint NOT NULL DEFAULT 0,
  lease_until timestamptz NOT NULL DEFAULT '1970-01-01', recovery_started_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS online_commands (
  match_id text NOT NULL REFERENCES online_matches(id), player_id text NOT NULL REFERENCES online_players(id),
  client_seq bigint NOT NULL CHECK(client_seq > 0), payload jsonb NOT NULL, payload_hash text NOT NULL,
  connection_epoch bigint NOT NULL, status text NOT NULL DEFAULT 'PENDING',
  received_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  apply_tick bigint NOT NULL, result jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY(match_id,player_id,client_seq)
);
CREATE INDEX IF NOT EXISTS online_pending_commands ON online_commands(match_id, apply_tick) WHERE status='PENDING';
CREATE TABLE IF NOT EXISTS online_batches (
  match_id text NOT NULL REFERENCES online_matches(id), batch_seq bigint NOT NULL,
  tick bigint NOT NULL, owner_epoch bigint NOT NULL, snapshot_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(match_id,batch_seq)
);
CREATE TABLE IF NOT EXISTS online_results (
  match_id text PRIMARY KEY REFERENCES online_matches(id), result_id text NOT NULL UNIQUE,
  winner integer NOT NULL CHECK(winner IN (-1,0,1,2)), reason text NOT NULL,
  tick bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS online_outbox (
  id text PRIMARY KEY, match_id text NOT NULL REFERENCES online_matches(id),
  type text NOT NULL, payload jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE online_matches ALTER COLUMN lease_until SET DEFAULT '1970-01-01'::timestamptz;
UPDATE online_matches SET lease_until='1970-01-01'::timestamptz WHERE lease_until='-infinity'::timestamptz;
