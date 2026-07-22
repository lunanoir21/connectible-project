use sqlx::SqlitePool;

use crate::error::Result;
use crate::proto::connectible::v1::{DeviceType, Identity, Platform};

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
}

impl DeviceRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
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
        sqlx::query("UPDATE devices SET cert_fingerprint = ?1 WHERE device_id = ?2")
            .bind(fingerprint)
            .bind(device_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// The pinned certificate fingerprint for a device, if any. `None` both
    /// for an unknown device and for a known device that has not been
    /// pinned yet (pre-TOFU). Convenience over `get(..).cert_fingerprint`.
    pub async fn fingerprint(&self, device_id: &str) -> Result<Option<String>> {
        Ok(self.get(device_id).await?.and_then(|r| r.cert_fingerprint))
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
        let repo = DeviceRepository::new(test_pool().await);
        let identity = sample_identity("dev-1");
        repo.upsert_paired(&identity, 1000).await.expect("upsert");

        let record = repo.get("dev-1").await.expect("get").expect("present");
        assert_eq!(record.device_name, "Test Device");
        assert_eq!(record.paired_at_ms, 1000);
    }

    #[tokio::test]
    async fn fingerprint_starts_null_then_records_and_reads_back() {
        let repo = DeviceRepository::new(test_pool().await);
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
        let repo = DeviceRepository::new(test_pool().await);
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
        let repo = DeviceRepository::new(test_pool().await);
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
        let repo = DeviceRepository::new(test_pool().await);
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
        let repo = DeviceRepository::new(test_pool().await);
        assert!(!repo.is_paired("does-not-exist").await.expect("is_paired"));
    }

    /// T-307: forgetting a paired device removes its row entirely (not
    /// just an online/connection flag), and re-inserting the same
    /// device_id afterward starts a brand new pairing lifetime rather
    /// than resurrecting the old one.
    #[tokio::test]
    async fn delete_removes_paired_device_and_is_idempotent() {
        let repo = DeviceRepository::new(test_pool().await);
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
}
