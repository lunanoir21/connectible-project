//! Pairing & device checks (Phase F / T-F4): the paired-device store is
//! readable, how many devices are paired, and their TOFU pinning status
//! (how many have a pinned certificate fingerprint yet, Phase C).

use async_trait::async_trait;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::Row;

use super::{Category, Check, CheckResult, DiagnosticsContext};

pub fn checks() -> Vec<Box<dyn Check>> {
    vec![Box::new(PairedStore)]
}

pub struct PairedStore;

#[async_trait]
impl Check for PairedStore {
    fn id(&self) -> &'static str {
        "paired-store"
    }
    fn title(&self) -> &'static str {
        "Paired devices"
    }
    fn category(&self) -> Category {
        Category::Pairing
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let db_path = &ctx.config.db_path;
        if !db_path.exists() {
            return CheckResult::ok(self, "No devices paired yet")
                .detail("The device database has not been created yet.")
                .with_data("paired", "0");
        }

        // Read-only so we never contend with the running daemon's writes;
        // a busy_timeout tolerates a momentary lock.
        let opts = SqliteConnectOptions::new()
            .filename(db_path)
            .read_only(true)
            .busy_timeout(std::time::Duration::from_secs(2));
        let pool = match SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(opts)
            .await
        {
            Ok(p) => p,
            Err(e) => {
                return CheckResult::ok(self, "Device database unreadable")
                    .error("Cannot open the device database")
                    .detail(format!("{}: {e}", db_path.display()))
                    .remediation("Check the file's permissions; if corrupt, re-pairing rebuilds it.");
            }
        };

        let rows = match sqlx::query("SELECT cert_fingerprint FROM devices")
            .fetch_all(&pool)
            .await
        {
            Ok(r) => r,
            Err(e) => {
                pool.close().await;
                return CheckResult::ok(self, "Device table unreadable")
                    .error("Cannot read the devices table")
                    .detail(e.to_string())
                    .remediation("The database may be from an incompatible version; re-pairing rebuilds it.");
            }
        };
        pool.close().await;

        let total = rows.len();
        let pinned = rows
            .iter()
            .filter(|r| {
                r.try_get::<Option<String>, _>("cert_fingerprint")
                    .ok()
                    .flatten()
                    .is_some_and(|s| !s.is_empty())
            })
            .count();

        let base = CheckResult::ok(self, format!("{total} paired, {pinned} with a pinned cert"))
            .with_data("paired", total.to_string())
            .with_data("pinned", pinned.to_string());

        if total > 0 && pinned < total {
            // Not an error: pre-TOFU devices backfill on their next connect
            // (T-C5). Surface it as info so the user understands the state.
            base.warn(format!(
                "{} device(s) not yet cert-pinned",
                total - pinned
            ))
            .remediation(
                "These were paired before certificate pinning; they pin automatically on the next connect.",
            )
        } else {
            base
        }
    }
}
