use std::path::Path;

use uuid::Uuid;

use crate::config::Config;
use crate::error::Result;
use crate::proto::connectible::v1::{DeviceType, Identity, Platform};

pub const PROTOCOL_VERSION: u32 = 1;
pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Loads this daemon's persisted `device_id` (a UUIDv4), generating and
/// persisting one on first run. The id must never be derived from
/// hostname/IP, both of which can change (see connectible.proto's
/// Identity.device_id comment).
pub fn load_or_create_device_id(config: &Config) -> Result<String> {
    let path = config.data_dir.join("device_id");
    if let Ok(existing) = std::fs::read_to_string(&path) {
        let trimmed = existing.trim().to_string();
        if !trimmed.is_empty() {
            return Ok(trimmed);
        }
    }
    let id = Uuid::new_v4().to_string();
    write_atomic(&path, &id)?;
    Ok(id)
}

fn write_atomic(path: &Path, contents: &str) -> Result<()> {
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, contents)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

fn current_platform() -> Platform {
    if cfg!(target_os = "windows") {
        Platform::Windows
    } else if cfg!(target_os = "macos") {
        Platform::Macos
    } else if cfg!(target_os = "linux") {
        match std::env::var("XDG_SESSION_TYPE").as_deref() {
            Ok("wayland") => Platform::LinuxWayland,
            _ => Platform::LinuxX11,
        }
    } else {
        Platform::Unspecified
    }
}

/// Builds the advertised capability list from the runtime backend
/// probes. Single source of truth shared by daemon startup (lib.rs)
/// and the GetLocalState RPC, so the two can never drift apart.
pub fn capability_list(clipboard_available: bool, remote_input_available: bool) -> Vec<String> {
    let mut capabilities = vec![
        "file_transfer".to_string(),
        "battery".to_string(),
        "notifications".to_string(),
    ];
    if clipboard_available {
        capabilities.push("clipboard".to_string());
    }
    if remote_input_available {
        capabilities.push("remote_input".to_string());
    }
    capabilities
}

pub fn build_local_identity(
    config: &Config,
    device_id: &str,
    capabilities: Vec<String>,
) -> Identity {
    Identity {
        device_id: device_id.to_string(),
        device_name: config.device_name.clone(),
        platform: current_platform() as i32,
        device_type: DeviceType::Desktop as i32,
        protocol_version: PROTOCOL_VERSION,
        app_version: APP_VERSION.to_string(),
        capabilities,
    }
}
