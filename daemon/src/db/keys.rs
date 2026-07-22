//! Sourcing the AES-256 key used to encrypt the `devices.cert_fingerprint`
//! column (Phase H; see `docs/design/db-encryption.md` for why only that
//! one column, and why application-level encryption rather than
//! SQLCipher). Three sources, tried in order:
//!
//! 1. `CONNECTIBLE_DB_KEY_FILE` env var (T-H5) -- explicit override for
//!    scripted/containerized deployments.
//! 2. The OS keyring via Secret Service (T-H2) -- generated on first use,
//!    read back on every later start.
//! 3. A `0600` key file under `<data_dir>/tls/` (T-H3) -- the fallback
//!    for a systemd user service with no session bus to reach a keyring
//!    through (headless/server use).

use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use rand::RngCore;
use tracing::{info, warn};

use crate::config::Config;
use crate::error::{DaemonError, Result};

pub const KEY_LEN: usize = 32;
const FALLBACK_KEY_FILE: &str = "db.key";
const KEYRING_SERVICE: &str = "connectibled";
const KEYRING_USERNAME: &str = "db-encryption-key";
/// How long to wait for a Secret Service D-Bus round trip before treating
/// it as unreachable and falling back (T-H3). Generous for a real desktop
/// session, short enough that a headless host with no session bus at all
/// (where the connection attempt itself may hang rather than error
/// quickly, depending on `DBUS_SESSION_BUS_ADDRESS`) doesn't stall daemon
/// startup.
const KEYRING_TIMEOUT: Duration = Duration::from_secs(3);

/// Where this key came from -- reported by the System Doctor (T-H6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeySource {
    EnvOverride,
    Keyring,
    FallbackFile,
}

impl KeySource {
    pub fn as_str(&self) -> &'static str {
        match self {
            KeySource::EnvOverride => "env override (CONNECTIBLE_DB_KEY_FILE)",
            KeySource::Keyring => "OS keyring (Secret Service)",
            KeySource::FallbackFile => "fallback key file",
        }
    }
}

pub struct DbKey {
    pub bytes: [u8; KEY_LEN],
    pub source: KeySource,
}

/// Loads (generating on first use) the database column-encryption key,
/// trying each source in priority order.
pub async fn load_or_create_db_key(config: &Config) -> Result<DbKey> {
    if let Ok(path) = std::env::var("CONNECTIBLE_DB_KEY_FILE") {
        let bytes = load_or_create_key_file(Path::new(&path))?;
        info!(path = %path, "db encryption key: using CONNECTIBLE_DB_KEY_FILE override");
        return Ok(DbKey {
            bytes,
            source: KeySource::EnvOverride,
        });
    }

    match try_keyring().await {
        Some(bytes) => {
            info!("db encryption key: using OS keyring (Secret Service)");
            Ok(DbKey {
                bytes,
                source: KeySource::Keyring,
            })
        }
        None => {
            let path = config.tls_dir.join(FALLBACK_KEY_FILE);
            warn!(
                path = %path.display(),
                "db encryption key: OS keyring unreachable (no session bus, or Secret Service \
                 not running) -- falling back to a local key file. This is expected for a \
                 headless systemd service; if you're on a desktop session and see this \
                 unexpectedly, check that a Secret Service provider (GNOME Keyring, KWallet, ...) \
                 is running."
            );
            let bytes = load_or_create_key_file(&path)?;
            Ok(DbKey {
                bytes,
                source: KeySource::FallbackFile,
            })
        }
    }
}

/// Reads a hex-encoded key from `path`, generating and writing a fresh
/// one (mode `0600`, matching `tls.rs`'s cert/key handling) if the file
/// doesn't exist yet.
fn load_or_create_key_file(path: &Path) -> Result<[u8; KEY_LEN]> {
    if path.exists() {
        let hex = std::fs::read_to_string(path)?;
        return decode_hex_key(hex.trim())
            .ok_or_else(|| DaemonError::Tls(format!("malformed db key file: {}", path.display())));
    }
    let bytes = random_key();
    write_key_file(path, &bytes)?;
    Ok(bytes)
}

fn write_key_file(path: &Path, bytes: &[u8; KEY_LEN]) -> Result<()> {
    use std::io::Write;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(hex::encode(bytes).as_bytes())?;
    Ok(())
}

fn random_key() -> [u8; KEY_LEN] {
    let mut bytes = [0u8; KEY_LEN];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes
}

fn decode_hex_key(hex_str: &str) -> Option<[u8; KEY_LEN]> {
    let decoded = hex::decode(hex_str).ok()?;
    decoded.try_into().ok()
}

/// Attempts to read (or, on first use, generate and store) the key via
/// the OS keyring, off the async executor since the underlying D-Bus
/// client is blocking. Returns `None` on any failure (unreachable
/// Secret Service, timeout, locked keyring, ...) so the caller falls
/// back rather than failing daemon startup outright.
async fn try_keyring() -> Option<[u8; KEY_LEN]> {
    let attempt = tokio::task::spawn_blocking(keyring_get_or_create);
    match tokio::time::timeout(KEYRING_TIMEOUT, attempt).await {
        Ok(Ok(Some(bytes))) => Some(bytes),
        Ok(Ok(None)) => None,
        Ok(Err(_)) => None, // the blocking task itself panicked
        Err(_) => None,     // timed out
    }
}

fn keyring_get_or_create() -> Option<[u8; KEY_LEN]> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, KEYRING_USERNAME).ok()?;
    match entry.get_password() {
        Ok(hex_str) => decode_hex_key(&hex_str),
        Err(keyring::Error::NoEntry) => {
            let bytes = random_key();
            entry.set_password(&hex::encode(bytes)).ok()?;
            Some(bytes)
        }
        Err(_) => None,
    }
}

/// Path the fallback key file would live at, for diagnostics (T-H6) --
/// does not create anything.
pub fn fallback_key_file_path(config: &Config) -> PathBuf {
    config.tls_dir.join(FALLBACK_KEY_FILE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn hex_round_trips_a_key() {
        let key = random_key();
        let hex_str = hex::encode(key);
        assert_eq!(decode_hex_key(&hex_str), Some(key));
    }

    #[test]
    fn decode_hex_key_rejects_wrong_length() {
        assert_eq!(decode_hex_key(&hex::encode([0u8; 16])), None);
    }

    #[test]
    fn decode_hex_key_rejects_non_hex() {
        assert_eq!(decode_hex_key("not hex at all"), None);
    }

    #[test]
    fn load_or_create_key_file_persists_across_calls() {
        let dir = std::env::temp_dir().join(format!(
            "connectibled-dbkey-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock before unix epoch")
                .as_nanos()
        ));
        let path = dir.join("db.key");

        let first = load_or_create_key_file(&path).expect("generate");
        let second = load_or_create_key_file(&path).expect("read back");
        assert_eq!(first, second, "second call must read back the same key, not regenerate");

        let mode = std::fs::metadata(&path)
            .expect("stat key file")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_or_create_key_file_rejects_a_malformed_existing_file() {
        let dir = std::env::temp_dir().join(format!(
            "connectibled-dbkey-bad-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock before unix epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("create dir");
        let path = dir.join("db.key");
        std::fs::write(&path, "not a valid hex key").expect("write malformed file");

        let result = load_or_create_key_file(&path);
        assert!(result.is_err(), "a malformed key file must be a hard error, not silently regenerated");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
