mod repository;

pub use repository::{DeviceRecord, DeviceRepository};

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;

use crate::config::Config;
use crate::error::Result;

/// Opens (creating if necessary) the SQLite database file at
/// `config.db_path` and applies all pending migrations. See
/// migrations/0001_init.sql for schema and the plaintext-storage note.
pub async fn init_pool(config: &Config) -> Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(&config.db_path)
        .create_if_missing(true);

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    sqlx::migrate!("./migrations").run(&pool).await?;

    Ok(pool)
}
