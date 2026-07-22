-- Devices known to this daemon: both currently-paired devices and
-- historical entries. Storage is plaintext in the MVP -- this is a
-- documented, accepted limitation (see RULES.md security checklist
-- and PLAN.md non-goals), not an oversight. Cert-fingerprint columns
-- are reserved for the v1.0 public-key-pinning work and unused here.
CREATE TABLE IF NOT EXISTS devices (
    device_id      TEXT PRIMARY KEY NOT NULL,
    device_name    TEXT NOT NULL,
    platform       TEXT NOT NULL,
    device_type    TEXT NOT NULL,
    paired_at_ms   INTEGER NOT NULL,
    last_seen_ms   INTEGER NOT NULL,
    cert_fingerprint TEXT
);

CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices (last_seen_ms);
