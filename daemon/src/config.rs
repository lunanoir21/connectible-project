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
///
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

/// Path to the small file persisting the UI toggle states (T-X12) --
/// remote-input (T-309) and clipboard-sync (T-310) -- across daemon
/// restarts, in the same `data_dir` as the download-dir override.
pub fn ui_toggles_path(data_dir: &Path) -> PathBuf {
    data_dir.join("ui_toggles")
}

/// Persisted enable states for the two UI toggles. Both default to
/// `true` (the pre-T-X12 behavior) whenever the file is absent or
/// unparseable, so a fresh install -- or a corrupt file -- simply means
/// "everything on" rather than surprising the user with things off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UiToggles {
    pub clipboard_sync_enabled: bool,
    pub remote_input_enabled: bool,
}

impl Default for UiToggles {
    fn default() -> Self {
        Self {
            clipboard_sync_enabled: true,
            remote_input_enabled: true,
        }
    }
}

/// Reads the persisted toggle states (T-X12). One `key=bool` per line
/// (`clipboard_sync=`, `remote_input=`), matching the plain-text
/// simplicity of the `download_dir` override rather than pulling in a
/// JSON dependency for two booleans. Any missing key keeps its default;
/// a missing or unreadable file yields all-defaults.
pub fn load_ui_toggles(data_dir: &Path) -> UiToggles {
    let mut toggles = UiToggles::default();
    if let Ok(raw) = std::fs::read_to_string(ui_toggles_path(data_dir)) {
        for line in raw.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let on = value.trim() == "true";
            match key.trim() {
                "clipboard_sync" => toggles.clipboard_sync_enabled = on,
                "remote_input" => toggles.remote_input_enabled = on,
                _ => {}
            }
        }
    }
    toggles
}

/// Persists both toggle states (T-X12). Both are written every time,
/// regardless of which one changed, so the file is always internally
/// consistent and a partial write can't leave a stale half.
pub fn write_ui_toggles(data_dir: &Path, toggles: UiToggles) -> std::io::Result<()> {
    std::fs::write(
        ui_toggles_path(data_dir),
        format!(
            "clipboard_sync={}\nremote_input={}\n",
            toggles.clipboard_sync_enabled, toggles.remote_input_enabled
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ui_toggles_default_to_all_on_when_absent() {
        let dir = tempfile::tempdir().expect("tempdir");
        let toggles = load_ui_toggles(dir.path());
        assert_eq!(toggles, UiToggles::default());
        assert!(toggles.clipboard_sync_enabled);
        assert!(toggles.remote_input_enabled);
    }

    #[test]
    fn ui_toggles_round_trip() {
        let dir = tempfile::tempdir().expect("tempdir");
        let written = UiToggles {
            clipboard_sync_enabled: false,
            remote_input_enabled: true,
        };
        write_ui_toggles(dir.path(), written).expect("write");
        assert_eq!(load_ui_toggles(dir.path()), written);

        let flipped = UiToggles {
            clipboard_sync_enabled: true,
            remote_input_enabled: false,
        };
        write_ui_toggles(dir.path(), flipped).expect("overwrite");
        assert_eq!(load_ui_toggles(dir.path()), flipped);
    }

    #[test]
    fn ui_toggles_missing_key_keeps_its_default() {
        let dir = tempfile::tempdir().expect("tempdir");
        // Only one key present, plus a junk line: the missing key must
        // keep its default (on), not flip to off.
        std::fs::write(ui_toggles_path(dir.path()), "remote_input=false\ngarbage\n")
            .expect("write partial");
        let toggles = load_ui_toggles(dir.path());
        assert!(toggles.clipboard_sync_enabled, "absent key defaults on");
        assert!(!toggles.remote_input_enabled);
    }
}
