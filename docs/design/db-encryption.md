# Device-store at-rest encryption (Phase H, T-H1)

Goal: close the plaintext-SQLite gap `PLAN.md`'s risk table and
`RULES.md`'s security checklist both flag as "accepted high risk...
track it as a v1.0 task" -- not a permanent design choice.

## What's actually sensitive in `devices`

From `daemon/migrations/0001_init.sql`:

```sql
CREATE TABLE devices (
    device_id      TEXT PRIMARY KEY NOT NULL,
    device_name    TEXT NOT NULL,
    platform       TEXT NOT NULL,
    device_type    TEXT NOT NULL,
    paired_at_ms   INTEGER NOT NULL,
    last_seen_ms   INTEGER NOT NULL,
    cert_fingerprint TEXT
);
```

`device_id`/`platform`/`device_type`/timestamps are already broadcast
in the clear over mDNS to anyone on the LAN -- encrypting them at rest
protects nothing an attacker with disk access couldn't already learn by
sniffing a broadcast. `device_name` is arguably mild PII (a device
named after its owner) but is likewise already sent in the clear over
the wire during pairing and mDNS advertisement; encrypting it at rest
while it's plaintext on every wire exchange would be security theater,
not a real improvement. `cert_fingerprint` (Phase G) is the one column
whose disclosure has a real consequence: it is the credential this
daemon uses to *authenticate* a peer. An attacker with read access to
the DB file could learn expected fingerprints and use that knowledge as
a building block in a broader impersonation attempt (still needs the
peer's private key to actually complete a handshake, but there's no
reason to hand out this bookkeeping for free).

**Decision: encrypt only `cert_fingerprint`.** Not the whole file, not
the whole row. This keeps `device_id`/`device_name`/timestamps queryable
and indexable exactly as today (the `idx_devices_last_seen` index is
unaffected) and keeps the blast radius of this whole phase small.

## Approach: application-level column encryption, not SQLCipher

Two real options were on the table:

**SQLCipher** (transparent full-database-file encryption, a drop-in
replacement for the SQLite C library used elsewhere too) -- rejected.
`daemon/Cargo.toml` uses `sqlx`'s `sqlite` feature, which links
`libsqlite3-sys` in `bundled` mode: plain C, no external crypto
dependency, and it cross-compiles to the `release.yml` pipeline's
static `musl` target without any special handling. SQLCipher's
encryption backend needs OpenSSL (or LibreSSL/BoringSSL) linked in, and
statically linking OpenSSL into a `musl` binary is a well-known source
of pain (musl's libc shims interact badly with OpenSSL's assumptions
around threading/locale/certain syscalls unless built with a
musl-specific OpenSSL configuration, which is extra build-pipeline
complexity this project does not currently carry anywhere else). It
would also mean every read of `devices` decrypts the *entire* database
file's key material up front rather than only the one sensitive column,
for no benefit here since nothing else in the table needs it.

**Application-level column encryption** (chosen): AES-256-GCM over just
the `cert_fingerprint` bytes, using a pure-Rust crate (`aes-gcm`, no C
dependency, builds on `musl` the same as everything else in this
codebase already does) before the value ever reaches `sqlx`. The rest
of the database stays a completely ordinary SQLite file -- no custom
build step, no new C toolchain requirement, no cross-compilation risk
introduced. `sqlx`'s existing connection/pool code in `daemon/src/db/
mod.rs` does not change at all; only `DeviceRepository::set_fingerprint`
/`fingerprint` (`daemon/src/db/repository.rs`) encrypt/decrypt at the
boundary.

## Key source and storage

The AES key itself must not live next to the data it protects (that
would just be obfuscation, not encryption). Source, in priority order:

1. `CONNECTIBLE_DB_KEY_FILE` env var, if set (T-H5) -- explicit
   override for scripted/containerized deployments.
2. OS keyring via the `keyring` crate's `zbus-secret-service-keyring-
   store` backend (T-H2) -- pure-Rust D-Bus client, no `libdbus` C
   dependency, so it does not reintroduce the static-linking problem
   SQLCipher would have. Works with GNOME Keyring, KWallet (via its
   Secret Service compat interface), and any other Secret-Service-
   compliant provider.
3. A key file under `<data_dir>/tls/db.key`, mode `0600`, generated on
   first use (T-H3) -- the fallback for a systemd user service with no
   active session bus (headless/server use, matching this project's own
   `docs/design/systemd-service.md` deployment model).

Whichever source is used, the key is generated once (32 random bytes,
`rand`, already a dependency) and persisted there; every subsequent
daemon start reads the same key back rather than regenerating it.

## Migration

An existing plaintext `cert_fingerprint` value (every device paired
before this phase shipped) is detected on read by a length/format check
(the encrypted form is nonce + ciphertext + tag, structurally
distinguishable from the plaintext lowercase-hex format) and
transparently re-encrypted on next write, rather than requiring a
blocking migration pass over the whole table at startup (T-H4 covers
the explicit re-encrypt-if-plaintext path in more detail). Devices
paired before Phase G have `cert_fingerprint = NULL` regardless and are
unaffected either way.
