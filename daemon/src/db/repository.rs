use aes_gcm::aead::{Aead, Generate, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use sqlx::SqlitePool;

use crate::error::{DaemonError, Result};
use crate::proto::connectible::v1::{DeviceType, Identity, Platform};

/// Prefix distinguishing an application-level-encrypted `cert_fingerprint`
/// value (Phase H) from the plaintext lowercase-hex format every value
/// used before this phase. Chosen over a length heuristic since it's
/// unambiguous and self-documenting in the raw DB file too.
const ENCRYPTED_PREFIX: &str = "enc1:";

/// Row shape for the `devices` table. Deliberately separate from the
/// wire-level `Identity` proto message -- this struct carries local-only
/// bookkeeping fields (paired_at_ms, last_seen_ms) that never cross the
/// network.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct DeviceRecord {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub device_type: String,
    pub paired_at_ms: i64,
    pub last_seen_ms: i64,
    pub cert_fingerprint: Option<String>,
}

/// CRUD access to the `devices` table (T-018). Every method returns
/// `Result<T, DaemonError>`; no panics on malformed input, per RULES.md.
#[derive(Clone)]
pub struct DeviceRepository {
    pool: SqlitePool,
    /// AES-256 key for the `cert_fingerprint` column (Phase H; see
    /// `docs/design/db-encryption.md`). Sourced once at startup
    /// (`db::keys::load_or_create_db_key`) and threaded through here
    /// rather than read fresh per call.
    fingerprint_key: [u8; 32],
}

impl DeviceRepository {
    pub fn new(pool: SqlitePool, fingerprint_key: [u8; 32]) -> Self {
        Self {
            pool,
            fingerprint_key,
        }
    }

    fn cipher(&self) -> Aes256Gcm {
        let key = Key::<Aes256Gcm>::from(self.fingerprint_key);
        Aes256Gcm::new(&key)
    }

    /// Encrypts a fingerprint value for storage. Always produces the
    /// `ENCRYPTED_PREFIX`-tagged form, including when re-encrypting a
    /// value that was read back in legacy plaintext form (T-H4's
    /// transparent-migration-on-write).
    fn encrypt_fingerprint(&self, plaintext: &str) -> String {
        let nonce = Nonce::generate();
        // `Aes256Gcm::encrypt` only fails on catastrophic misuse (e.g. a
        // plaintext far beyond the format's length limit) -- never for a
        // ~64-byte hex fingerprint string, so this is not a fallible path
        // worth propagating as a `Result` up through every caller.
        let ciphertext = self
            .cipher()
            .encrypt(&nonce, plaintext.as_bytes())
            .expect("fingerprint plaintext is always well within AES-GCM's size limits");
        let mut combined = Vec::with_capacity(nonce.len() + ciphertext.len());
        combined.extend_from_slice(&nonce);
        combined.extend_from_slice(&ciphertext);
        format!("{ENCRYPTED_PREFIX}{}", hex::encode(combined))
    }

    /// Decrypts a stored fingerprint value. A value with no
    /// `ENCRYPTED_PREFIX` is assumed to be a pre-Phase-H plaintext
    /// fingerprint and returned as-is (T-H4) -- it is upgraded to the
    /// encrypted form the next time it's written via `set_fingerprint`,
    /// or explicitly by `migrate_plaintext_fingerprints`. A prefixed
    /// value that fails to decrypt (wrong key, or genuine corruption) is
    /// a hard error rather than silently treated as "no pin" -- that
    /// would silently drop TOFU protection instead of surfacing the
    /// problem.
    fn decrypt_fingerprint(&self, stored: &str) -> Result<String> {
        let Some(hex_str) = stored.strip_prefix(ENCRYPTED_PREFIX) else {
            return Ok(stored.to_string());
        };
        let combined = hex::decode(hex_str)
            .map_err(|e| DaemonError::Tls(format!("malformed encrypted fingerprint: {e}")))?;
        if combined.len() < 12 {
            return Err(DaemonError::Tls(
                "encrypted fingerprint shorter than a nonce".to_string(),
            ));
        }
        let (nonce_bytes, ciphertext) = combined.split_at(12);
        let nonce = Nonce::try_from(nonce_bytes)
            .map_err(|_| DaemonError::Tls("malformed nonce in stored fingerprint".to_string()))?;
        let plaintext = self.cipher().decrypt(&nonce, ciphertext).map_err(|_| {
            DaemonError::Tls(
                "failed to decrypt stored fingerprint (wrong db key, or corrupted data)"
                    .to_string(),
            )
        })?;
        String::from_utf8(plaintext)
            .map_err(|e| DaemonError::Tls(format!("decrypted fingerprint is not valid utf-8: {e}")))
    }

    /// Re-encrypts every paired device's plaintext (pre-Phase-H)
    /// `cert_fingerprint` in place (T-H4). Safe to call on every daemon
    /// startup -- a no-op once every value is already in the encrypted
    /// form. Returns the number of rows migrated.
    pub async fn migrate_plaintext_fingerprints(&self) -> Result<usize> {
        let rows = sqlx::query_as::<_, DeviceRecord>(
            "SELECT * FROM devices WHERE cert_fingerprint IS NOT NULL",
        )
        .fetch_all(&self.pool)
        .await?;

        let mut migrated = 0usize;
        for row in rows {
            let Some(stored) = row.cert_fingerprint else {
                continue;
            };
            if stored.starts_with(ENCRYPTED_PREFIX) {
                continue;
            }
            // `stored` is plaintext by construction here (no prefix);
            // encrypt it and verify the round trip before writing, so a
            // migration bug can never silently corrupt a working pin.
            let encrypted = self.encrypt_fingerprint(&stored);
            let verify = self.decrypt_fingerprint(&encrypted)?;
            if verify != stored {
                return Err(DaemonError::Tls(
                    "fingerprint migration round-trip check failed; refusing to write".to_string(),
                ));
            }
            sqlx::query("UPDATE devices SET cert_fingerprint = ?1 WHERE device_id = ?2")
                .bind(&encrypted)
                .bind(&row.device_id)
                .execute(&self.pool)
                .await?;
            migrated += 1;
        }
        Ok(migrated)
    }

    /// Inserts a new paired device, or refreshes `last_seen_ms` (and
    /// metadata) for an already-paired one, without touching its
    /// original `paired_at_ms` (T-015 duplicate-pairing short-circuit
    /// relies on this not resetting the pairing timestamp).
    pub async fn upsert_paired(&self, identity: &Identity, now_ms: i64) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO devices (device_id, device_name, platform, device_type, paired_at_ms, last_seen_ms)
            VALUES (?1, ?2, ?3, ?4, ?5, ?5)
            ON CONFLICT(device_id) DO UPDATE SET
                device_name = excluded.device_name,
                platform = excluded.platform,
                device_type = excluded.device_type,
                last_seen_ms = excluded.last_seen_ms
            "#,
        )
        .bind(&identity.device_id)
        .bind(&identity.device_name)
        .bind(
            Platform::try_from(identity.platform)
                .unwrap_or(Platform::Unspecified)
                .as_str_name(),
        )
        .bind(
            DeviceType::try_from(identity.device_type)
                .unwrap_or(DeviceType::Unspecified)
                .as_str_name(),
        )
        .bind(now_ms)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Records (pins) the peer's TLS certificate fingerprint for a paired
    /// device (T-C2, TOFU). Called on the record-on-first-use path when a
    /// device has no pin yet (a fresh pair, or the T-C5 backfill of a
    /// pre-TOFU device). Overwriting an existing pin is intentionally the
    /// caller's decision (only done via an explicit forget+re-pair), so
    /// this method itself just writes what it is given. No-op for an
    /// unknown device_id.
    pub async fn set_fingerprint(&self, device_id: &str, fingerprint: &str) -> Result<()> {
        let encrypted = self.encrypt_fingerprint(fingerprint);
        sqlx::query("UPDATE devices SET cert_fingerprint = ?1 WHERE device_id = ?2")
            .bind(encrypted)
            .bind(device_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// The pinned certificate fingerprint for a device, if any. `None` both
    /// for an unknown device and for a known device that has not been
    /// pinned yet (pre-TOFU). Decrypts the stored value (Phase H); a
    /// value stored before this phase shipped is plaintext and passed
    /// through unchanged (T-H4).
    pub async fn fingerprint(&self, device_id: &str) -> Result<Option<String>> {
        let Some(stored) = self.get(device_id).await?.and_then(|r| r.cert_fingerprint) else {
            return Ok(None);
        };
        self.decrypt_fingerprint(&stored).map(Some)
    }

    pub async fn update_last_seen(&self, device_id: &str, now_ms: i64) -> Result<()> {
        sqlx::query("UPDATE devices SET last_seen_ms = ?1 WHERE device_id = ?2")
            .bind(now_ms)
            .bind(device_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn get(&self, device_id: &str) -> Result<Option<DeviceRecord>> {
        let record =
            sqlx::query_as::<_, DeviceRecord>("SELECT * FROM devices WHERE device_id = ?1")
                .bind(device_id)
                .fetch_optional(&self.pool)
                .await?;
        Ok(record)
    }

    pub async fn is_paired(&self, device_id: &str) -> Result<bool> {
        Ok(self.get(device_id).await?.is_some())
    }

    pub async fn list(&self) -> Result<Vec<DeviceRecord>> {
        let records =
            sqlx::query_as::<_, DeviceRecord>("SELECT * FROM devices ORDER BY last_seen_ms DESC")
                .fetch_all(&self.pool)
                .await?;
        Ok(records)
    }

    /// Permanently removes a paired device's row (T-307's "Forget
    /// device" action, distinct from the online-attribution-only
    /// `disconnect_device` on `PeerRegistry`). Returns whether a row
    /// was actually deleted -- forgetting an already-unknown device_id
    /// is a no-op, not an error, mirroring `disconnect_device`'s
    /// `was_connected` semantics.
    pub async fn delete(&self, device_id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM devices WHERE device_id = ?1")
            .bind(device_id)
            .execute(&self.pool)
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::connectible::v1::{DeviceType, Platform};
    use sqlx::sqlite::SqlitePoolOptions;

    async fn test_pool() -> SqlitePool {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("in-memory sqlite connect");
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .expect("run migrations");
        pool
    }

    fn test_key() -> [u8; 32] {
        [7u8; 32]
    }

    fn sample_identity(id: &str) -> Identity {
        Identity {
            device_id: id.to_string(),
            device_name: "Test Device".to_string(),
            platform: Platform::LinuxX11 as i32,
            device_type: DeviceType::Desktop as i32,
            protocol_version: 1,
            app_version: "0.1.0".to_string(),
            capabilities: vec![],
        }
    }

    #[tokio::test]
    async fn insert_then_get() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        let identity = sample_identity("dev-1");
        repo.upsert_paired(&identity, 1000).await.expect("upsert");

        let record = repo.get("dev-1").await.expect("get").expect("present");
        assert_eq!(record.device_name, "Test Device");
        assert_eq!(record.paired_at_ms, 1000);
    }

    #[tokio::test]
    async fn fingerprint_starts_null_then_records_and_reads_back() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        let identity = sample_identity("dev-fp");
        repo.upsert_paired(&identity, 1000).await.expect("upsert");

        // Pre-TOFU: no pin yet (T-C5 backfill target).
        assert_eq!(repo.fingerprint("dev-fp").await.expect("fp"), None);

        // Record-on-first-use pins it.
        repo.set_fingerprint("dev-fp", "abc123").await.expect("set");
        assert_eq!(
            repo.fingerprint("dev-fp").await.expect("fp"),
            Some("abc123".to_string())
        );

        // Unknown device has no pin.
        assert_eq!(repo.fingerprint("nope").await.expect("fp"), None);
    }

    #[tokio::test]
    async fn upsert_paired_preserves_a_recorded_fingerprint() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        let identity = sample_identity("dev-fp2");
        repo.upsert_paired(&identity, 1000).await.expect("upsert");
        repo.set_fingerprint("dev-fp2", "pinned")
            .await
            .expect("set");
        // A later metadata refresh (reconnect) must not wipe the pin.
        repo.upsert_paired(&identity, 2000)
            .await
            .expect("re-upsert");
        assert_eq!(
            repo.fingerprint("dev-fp2").await.expect("fp"),
            Some("pinned".to_string())
        );
    }

    #[tokio::test]
    async fn repair_preserves_paired_at() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        let identity = sample_identity("dev-2");
        repo.upsert_paired(&identity, 1000)
            .await
            .expect("first upsert");
        repo.upsert_paired(&identity, 5000)
            .await
            .expect("second upsert");

        let record = repo.get("dev-2").await.expect("get").expect("present");
        assert_eq!(
            record.paired_at_ms, 1000,
            "paired_at_ms must not reset on repair"
        );
        assert_eq!(record.last_seen_ms, 5000);
    }

    #[tokio::test]
    async fn list_orders_by_last_seen_desc() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        repo.upsert_paired(&sample_identity("dev-a"), 1000)
            .await
            .expect("a");
        repo.upsert_paired(&sample_identity("dev-b"), 2000)
            .await
            .expect("b");

        let all = repo.list().await.expect("list");
        assert_eq!(all[0].device_id, "dev-b");
        assert_eq!(all[1].device_id, "dev-a");
    }

    #[tokio::test]
    async fn unknown_device_is_not_paired() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        assert!(!repo.is_paired("does-not-exist").await.expect("is_paired"));
    }

    /// T-307: forgetting a paired device removes its row entirely (not
    /// just an online/connection flag), and re-inserting the same
    /// device_id afterward starts a brand new pairing lifetime rather
    /// than resurrecting the old one.
    #[tokio::test]
    async fn delete_removes_paired_device_and_is_idempotent() {
        let repo = DeviceRepository::new(test_pool().await, test_key());
        let identity = sample_identity("dev-forget");
        repo.upsert_paired(&identity, 1000).await.expect("upsert");
        assert!(repo.is_paired("dev-forget").await.expect("is_paired"));

        let removed = repo.delete("dev-forget").await.expect("delete");
        assert!(
            removed,
            "an existing paired device must report removed=true"
        );
        assert!(!repo.is_paired("dev-forget").await.expect("is_paired"));

        // Forgetting an already-unknown device is a no-op, not an error.
        let repeat = repo.delete("dev-forget").await.expect("delete again");
        assert!(!repeat, "forgetting an already-unpaired device is a no-op");

        // Re-pairing afterward starts a fresh paired_at_ms, proving the
        // old row is truly gone rather than merely hidden.
        repo.upsert_paired(&identity, 9000)
            .await
            .expect("re-pair after forget");
        let record = repo
            .get("dev-forget")
            .await
            .expect("get")
            .expect("re-paired");
        assert_eq!(record.paired_at_ms, 9000);
    }

    /// T-H4: a fingerprint stored before Phase H shipped is plaintext
    /// (no `ENCRYPTED_PREFIX`) -- simulated here by writing the raw
    /// column value directly, bypassing `set_fingerprint`, exactly as a
    /// pre-Phase-H binary would have. `migrate_plaintext_fingerprints`
    /// must re-encrypt it in place without losing the value or touching
    /// already-encrypted rows.
    #[tokio::test]
    async fn migrate_plaintext_fingerprints_encrypts_legacy_rows_only() {
        let pool = test_pool().await;
        let repo = DeviceRepository::new(pool.clone(), test_key());
        repo.upsert_paired(&sample_identity("dev-legacy"), 1000)
            .await
            .expect("upsert legacy");
        repo.upsert_paired(&sample_identity("dev-already-enc"), 1000)
            .await
            .expect("upsert already-encrypted");

        // Legacy plaintext write, bypassing set_fingerprint's encryption.
        sqlx::query("UPDATE devices SET cert_fingerprint = ?1 WHERE device_id = ?2")
            .bind("deadbeef00000000000000000000000000000000000000000000000000ab")
            .bind("dev-legacy")
            .execute(&pool)
            .await
            .expect("write legacy plaintext fingerprint");
        // Already migrated (or paired fresh under Phase H).
        repo.set_fingerprint("dev-already-enc", "cafef00d")
            .await
            .expect("set encrypted fingerprint");

        let migrated = repo
            .migrate_plaintext_fingerprints()
            .await
            .expect("migrate");
        assert_eq!(migrated, 1, "only the legacy row should be migrated");

        // The on-disk value is no longer the plaintext string...
        let raw: (Option<String>,) =
            sqlx::query_as("SELECT cert_fingerprint FROM devices WHERE device_id = ?1")
                .bind("dev-legacy")
                .fetch_one(&pool)
                .await
                .expect("raw select");
        assert_ne!(
            raw.0.as_deref(),
            Some("deadbeef00000000000000000000000000000000000000000000000000ab"),
            "the on-disk value must no longer be plaintext-readable after migration"
        );
        assert!(raw.0.as_deref().unwrap().starts_with(ENCRYPTED_PREFIX));

        // ...but it still reads back correctly through the repository.
        assert_eq!(
            repo.fingerprint("dev-legacy").await.expect("fp"),
            Some("deadbeef00000000000000000000000000000000000000000000000000ab".to_string())
        );

        // A second migration pass is a no-op (nothing left to migrate).
        let second_pass = repo
            .migrate_plaintext_fingerprints()
            .await
            .expect("second migrate");
        assert_eq!(second_pass, 0);
    }

    /// T-H7: opening (decrypting) a fingerprint encrypted under a
    /// *different* key fails cleanly with a typed error, never a panic,
    /// and never silently treated as "no pin" (which would drop TOFU
    /// protection outright).
    #[tokio::test]
    async fn wrong_key_fails_to_decrypt_cleanly_instead_of_panicking() {
        let pool = test_pool().await;
        let writer = DeviceRepository::new(pool.clone(), test_key());
        writer
            .upsert_paired(&sample_identity("dev-wrongkey"), 1000)
            .await
            .expect("upsert");
        writer
            .set_fingerprint("dev-wrongkey", "abc123")
            .await
            .expect("set");

        let reader = DeviceRepository::new(pool, [42u8; 32]);
        let result = reader.fingerprint("dev-wrongkey").await;
        assert!(
            result.is_err(),
            "decrypting with the wrong key must be a typed error, not Ok(None) or a panic"
        );
    }

    /// T-H7: encryption must not change the pool's concurrent-access
    /// behavior -- several connections reading/writing different
    /// devices' fingerprints at once still all succeed and each sees a
    /// consistent, correctly round-tripped value, same as the
    /// pre-encryption baseline (`sqlx`'s own pool/locking handles the
    /// actual concurrency; this proves the new encrypt/decrypt step
    /// introduced no shared mutable state that would break under it).
    #[tokio::test]
    async fn concurrent_fingerprint_writes_all_round_trip_correctly() {
        // A real multi-connection pool needs a file-backed database --
        // `sqlite::memory:` gives each pooled connection its own
        // independent empty database, which would make this test
        // meaningless (every read would see nothing the other
        // connections wrote). `test_pool()` above sidesteps this by
        // capping at one connection; this test specifically wants more
        // than one to exercise real concurrent access.
        let dir = std::env::temp_dir().join(format!(
            "connectibled-concurrent-fp-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock before unix epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        let db_path = dir.join("test.db");
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(&db_path)
            .create_if_missing(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(options)
            .await
            .expect("file-backed sqlite connect");
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .expect("run migrations");
        let repo = DeviceRepository::new(pool, test_key());

        for i in 0..10 {
            repo.upsert_paired(&sample_identity(&format!("dev-c{i}")), 1000)
                .await
                .expect("upsert");
        }

        let mut tasks = Vec::new();
        for i in 0..10 {
            let repo = repo.clone();
            tasks.push(tokio::spawn(async move {
                let fp = format!("fingerprint-{i}");
                repo.set_fingerprint(&format!("dev-c{i}"), &fp)
                    .await
                    .expect("concurrent set");
                let read_back = repo
                    .fingerprint(&format!("dev-c{i}"))
                    .await
                    .expect("concurrent get");
                assert_eq!(read_back, Some(fp));
            }));
        }
        for task in tasks {
            task.await.expect("task panicked");
        }

        let _ = std::fs::remove_dir_all(&dir);
    }
}
