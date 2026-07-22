use sqlx::SqlitePool;

use crate::error::Result;

/// Hard cap on retained rows (T-J3) -- unbounded growth here is exactly
/// the pattern this codebase's own audit has flagged elsewhere (rate
/// limiter maps, upload ticket registry). Trimmed on every `record`
/// call rather than a separate background task, since that keeps the
/// table bounded with no extra moving parts at this data volume.
const MAX_ROWS: i64 = 500;

/// Row shape for the `transfer_history` table (Phase J). Mirrors the
/// wire-level `TransferHistoryEntry` proto message field-for-field,
/// but kept as its own type (like `DeviceRecord`/`Identity`) so a
/// local-only bookkeeping shape doesn't get coupled to the wire format.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct TransferHistoryRecord {
    pub transfer_id: String,
    pub peer_device_id: String,
    pub file_name: String,
    pub total_bytes: i64,
    pub direction: String,
    pub status: String,
    pub started_at_ms: i64,
    pub finished_at_ms: i64,
}

/// A new row to persist. Separate from `TransferHistoryRecord` (which
/// also carries `id` implicitly via row order) purely for call-site
/// clarity at `record()`.
#[derive(Debug, Clone)]
pub struct NewTransferHistoryEntry {
    pub transfer_id: String,
    pub peer_device_id: String,
    pub file_name: String,
    pub total_bytes: i64,
    pub direction: String,
    pub status: String,
    pub started_at_ms: i64,
    pub finished_at_ms: i64,
}

/// CRUD access to the `transfer_history` table. Every method returns
/// `Result<T, DaemonError>`; no panics on malformed input, per RULES.md.
#[derive(Clone)]
pub struct TransferHistoryRepository {
    pool: SqlitePool,
}

impl TransferHistoryRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// Inserts one terminal-state row, then trims the table back to
    /// `MAX_ROWS` (T-J3), keeping the most recently finished rows.
    pub async fn record(&self, entry: &NewTransferHistoryEntry) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO transfer_history
                (transfer_id, peer_device_id, file_name, total_bytes, direction, status, started_at_ms, finished_at_ms)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
        )
        .bind(&entry.transfer_id)
        .bind(&entry.peer_device_id)
        .bind(&entry.file_name)
        .bind(entry.total_bytes)
        .bind(&entry.direction)
        .bind(&entry.status)
        .bind(entry.started_at_ms)
        .bind(entry.finished_at_ms)
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            DELETE FROM transfer_history
            WHERE id NOT IN (SELECT id FROM transfer_history ORDER BY id DESC LIMIT ?1)
            "#,
        )
        .bind(MAX_ROWS)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Most-recently-finished rows first, capped at `limit` (0 or
    /// negative falls back to `MAX_ROWS` -- a caller asking for
    /// "everything" gets exactly the retention cap, never an
    /// accidental full unbounded scan).
    pub async fn list(&self, limit: i64) -> Result<Vec<TransferHistoryRecord>> {
        let limit = if limit > 0 { limit } else { MAX_ROWS };
        let records = sqlx::query_as::<_, TransferHistoryRecord>(
            "SELECT transfer_id, peer_device_id, file_name, total_bytes, direction, status, started_at_ms, finished_at_ms
             FROM transfer_history ORDER BY id DESC LIMIT ?1",
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(records)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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

    fn entry(transfer_id: &str, direction: &str, status: &str, finished_at_ms: i64) -> NewTransferHistoryEntry {
        NewTransferHistoryEntry {
            transfer_id: transfer_id.to_string(),
            peer_device_id: "dev-1".to_string(),
            file_name: "report.pdf".to_string(),
            total_bytes: 1024,
            direction: direction.to_string(),
            status: status.to_string(),
            started_at_ms: finished_at_ms - 500,
            finished_at_ms,
        }
    }

    #[tokio::test]
    async fn record_then_list_round_trips() {
        let repo = TransferHistoryRepository::new(test_pool().await);
        repo.record(&entry("t-1", "incoming", "completed", 1000))
            .await
            .expect("record");

        let rows = repo.list(10).await.expect("list");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].transfer_id, "t-1");
        assert_eq!(rows[0].direction, "incoming");
        assert_eq!(rows[0].status, "completed");
        assert_eq!(rows[0].total_bytes, 1024);
    }

    #[tokio::test]
    async fn list_orders_most_recent_first() {
        let repo = TransferHistoryRepository::new(test_pool().await);
        repo.record(&entry("t-a", "incoming", "completed", 1000))
            .await
            .expect("a");
        repo.record(&entry("t-b", "outgoing", "failed", 2000))
            .await
            .expect("b");

        let rows = repo.list(10).await.expect("list");
        assert_eq!(rows[0].transfer_id, "t-b");
        assert_eq!(rows[1].transfer_id, "t-a");
    }

    /// T-J3: unbounded growth is capped at MAX_ROWS, keeping the most
    /// recent entries once the cap is exceeded.
    #[tokio::test]
    async fn seeding_past_the_cap_trims_to_the_most_recent_rows() {
        let repo = TransferHistoryRepository::new(test_pool().await);
        for i in 0..(MAX_ROWS + 100) {
            repo.record(&entry(&format!("t-{i}"), "incoming", "completed", i))
                .await
                .expect("record");
        }

        let rows = repo.list(MAX_ROWS + 100).await.expect("list");
        assert_eq!(rows.len() as i64, MAX_ROWS, "table must be trimmed to the cap");
        // Most recent (highest finished_at_ms / id) first.
        assert_eq!(rows[0].transfer_id, format!("t-{}", MAX_ROWS + 99));
        // The oldest surviving row is exactly the cap-th most recent.
        assert_eq!(rows[rows.len() - 1].transfer_id, "t-100");
    }

    #[tokio::test]
    async fn zero_or_negative_limit_falls_back_to_the_cap() {
        let repo = TransferHistoryRepository::new(test_pool().await);
        repo.record(&entry("t-1", "incoming", "completed", 1000))
            .await
            .expect("record");

        assert_eq!(repo.list(0).await.expect("list zero").len(), 1);
        assert_eq!(repo.list(-5).await.expect("list negative").len(), 1);
    }
}
