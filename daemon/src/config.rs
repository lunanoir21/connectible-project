use std::path::{Path, PathBuf};

use directories::{ProjectDirs, UserDirs};

/// Runtime configuration and on-disk layout, matching the storage layout
/// documented in ARCHITECTURE.md section 4.
#[derive(Debug, Clone)]
pub struct Config {
    pub data_dir: PathBuf,
    pub tls_dir: PathBuf,
    pub transfers_dir: PathBuf,
    pub db_path: PathBuf,
    pub grpc_port: u16,
    pub device_name: String,
}

impl Config {
    pub fn load() -> crate::error::Result<Self> {
        let dirs = ProjectDirs::from("io", "connectible", "connectibled")
            .ok_or_else(|| crate::error::DaemonError::Tls("no home directory".into()))?;
        let data_dir = dirs.data_dir().to_path_buf();
        let tls_dir = data_dir.join("tls");
        let transfers_dir = data_dir.join("transfers");
        std::fs::create_dir_all(&data_dir)?;
        std::fs::create_dir_all(&tls_dir)?;
        std::fs::create_dir_all(&transfers_dir)?;

        let db_path = data_dir.join("connectibled.db");

        let grpc_port = std::env::var("CONNECTIBLE_PORT")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(58231);

        let device_name = std::env::var("CONNECTIBLE_DEVICE_NAME").unwrap_or_else(|_| {
            hostname::get()
                .ok()
                .and_then(|h| h.into_string().ok())
                .unwrap_or_else(|| "Connectible Device".to_string())
        });

        Ok(Self {
            data_dir,
            tls_dir,
            transfers_dir,
            db_path,
            grpc_port,
            device_name,
        })
    }
}

/// Path of the single-line file recording the user's chosen
/// received-files directory. Written by the desktop Settings picker
/// (`set_download_dir`) into the daemon's `data_dir` -- the same
/// loopback-shared directory the cert and device_id already live in --
/// and read back by [`resolve_download_dir`]. Absent means "use the OS
/// Downloads folder".
pub fn download_dir_config_path(data_dir: &Path) -> PathBuf {
    data_dir.join("download_dir")
}

/// Directory finalized (received) files are written to, resolved fresh
/// each call so a Settings change takes effect without restarting the
/// daemon. Resolution order:
///   1. the user's configured path (`download_dir` override file), if set
///      and creatable;
///   2. the OS Downloads folder (`~/Downloads` on Linux), if creatable;
///   3. `data_dir/received` as a last resort.
/// Each candidate is `create_dir_all`'d and only accepted if that
/// succeeds, so a stale or unwritable configured path silently falls
/// through instead of hard-failing an incoming transfer.
pub fn resolve_download_dir(data_dir: &Path) -> PathBuf {
    if let Ok(raw) = std::fs::read_to_string(download_dir_config_path(data_dir)) {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let configured = PathBuf::from(trimmed);
            if std::fs::create_dir_all(&configured).is_ok() {
                return configured;
            }
        }
    }
    if let Some(dl) = UserDirs::new().and_then(|d| d.download_dir().map(Path::to_path_buf)) {
        if std::fs::create_dir_all(&dl).is_ok() {
            return dl;
        }
    }
    let fallback = data_dir.join("received");
    let _ = std::fs::create_dir_all(&fallback);
    fallback
}

/// Persists `dir` as the received-files directory for [`resolve_download_dir`]
/// to pick up. Called from the desktop UI via a Tauri command; writes into
/// the daemon's `data_dir` so the (separate) daemon process reads the same
/// value.
pub fn write_download_dir(data_dir: &Path, dir: &Path) -> std::io::Result<()> {
    std::fs::write(
        download_dir_config_path(data_dir),
        dir.to_string_lossy().as_bytes(),
    )
}
