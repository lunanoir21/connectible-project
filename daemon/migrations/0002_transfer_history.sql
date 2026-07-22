-- Persisted transfer history (Phase J). `id` is a synthetic
-- autoincrement key rather than using `transfer_id` as the primary key
-- -- the same transfer_id can legitimately recur across retried
-- attempts (a resumed upload reuses its file_id) and is not unique
-- over the table's lifetime, only within one live attempt.
CREATE TABLE IF NOT EXISTS transfer_history (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    transfer_id    TEXT NOT NULL,
    peer_device_id TEXT NOT NULL,
    file_name      TEXT NOT NULL,
    total_bytes    INTEGER NOT NULL,
    direction      TEXT NOT NULL,
    status         TEXT NOT NULL,
    started_at_ms  INTEGER NOT NULL,
    finished_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_transfer_history_finished ON transfer_history (finished_at_ms);
