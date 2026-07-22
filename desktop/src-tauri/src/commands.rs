use connectible_desktop_core::dto::{DeviceDto, LocalStateDto, TransferProgressDto};
use connectible_desktop_core::local::{default_daemon_data_dir, default_daemon_port, ui_identity, LocalDaemonClient};
use connectible_desktop_core::remote::{PairOutcome, RemoteDeviceClient};
use connectible_desktop_core::DesktopError;
use std::process::{Command, Stdio};
use std::sync::Arc;
use tokio::sync::Mutex;

/// Global handle to the daemon child process (if we started it).
static DAEMON_PROCESS: Mutex<Option<Arc<Mutex<std::process::Child>>>> = Mutex::const_new(None);
use tauri::State;

use crate::state::AppState;

/// Structured error the frontend receives in place of a bare string
/// (T-602): `code` is the wire `ErrorCode`'s name (e.g.
/// `"DEVICE_NOT_FOUND"`), the key `desktop/src/lib/errors.ts`'s
/// `errorCodeMessage` looks a translated, actionable message up by.
/// `message` is kept only for logs/dev tooling -- panels must not
/// render it directly to the user (RULES.md: "do not show raw gRPC
/// status text to end users").
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CmdError {
    pub code: &'static str,
    pub message: String,
}

impl CmdError {
    /// Built from a condition that has no matching wire `ErrorCode`
    /// (e.g. "the Tauri shell has no daemon client yet") -- reported to
    /// the frontend as UNSPECIFIED, the proto's own catch-all.
    fn unspecified(message: impl Into<String>) -> Self {
        Self {
            code: "UNSPECIFIED",
            message: message.into(),
        }
    }
}

impl From<DesktopError> for CmdError {
    fn from(err: DesktopError) -> Self {
        Self {
            code: err.code_name(),
            message: err.to_string(),
        }
    }
}

/// Commands return `Result<T, CmdError>` (T-602) instead of a bare
/// `String` so the frontend gets a structured, matchable error code
/// rather than only Rust's `Display` text.
type CmdResult<T> = Result<T, CmdError>;

async fn require_client(
    state: &State<'_, AppState>,
) -> CmdResult<connectible_desktop_core::LocalDaemonClient> {
    state
        .client()
        .await
        .ok_or_else(|| CmdError::unspecified("daemon not connected yet"))
}

/// Connects to a remote peer enforcing TOFU (Phase C / T-C3): fetches the
/// target device's pinned certificate fingerprint from the daemon and
/// requires the peer to present it -- a mismatch surfaces
/// `FINGERPRINT_CHANGED` instead of silently trusting a changed key. For a
/// device with no pin yet (a pre-TOFU device on its first post-upgrade
/// connect), the observed fingerprint is recorded on first use (T-C2/C5).
/// `device_id` is the *target* peer's id.
async fn connect_with_tofu(
    daemon: &connectible_desktop_core::LocalDaemonClient,
    addr: &str,
    port: u16,
    device_id: &str,
) -> CmdResult<RemoteDeviceClient> {
    let pinned = daemon.pinned_fingerprint(device_id).await.ok().flatten();
    let had_pin = pinned.is_some();
    let (data_dir, _) = daemon_endpoint();
    let remote = RemoteDeviceClient::connect_pinned(&data_dir, addr, port, pinned)
        .await
        .map_err(CmdError::from)?;
    if !had_pin {
        if let Some(fp) = remote.observed_fingerprint() {
            // Best-effort record-on-first-use / backfill; a no-op if the
            // device is not a known paired peer (pairing records it
            // explicitly in confirm_pin once the device is persisted).
            let _ = daemon.record_fingerprint(device_id, &fp).await;
        }
    }
    Ok(remote)
}

#[tauri::command]
pub async fn daemon_connected(state: State<'_, AppState>) -> CmdResult<bool> {
    Ok(state.is_connected().await)
}

/// Tries to connect to the local daemon and returns its status.
/// Useful for "Reconnect" button in settings.
#[tauri::command]
pub async fn daemon_status() -> CmdResult<DaemonStatusDto> {
    let (data_dir, port) = daemon_endpoint();
    
    match LocalDaemonClient::connect(data_dir, port).await {
        Ok(client) => {
            // Try a quick ping to verify it's responsive
            match client.ping_rtt_ms().await {
                Ok(rtt) => Ok(DaemonStatusDto {
                    running: true,
                    reachable: true,
                    rtt_ms: Some(rtt),
                    error_code: None,
                }),
                Err(e) => Ok(DaemonStatusDto {
                    running: true,
                    reachable: false,
                    rtt_ms: None,
                    error_code: Some(e.code_name()),
                }),
            }
        }
        Err(e) => Ok(DaemonStatusDto {
            running: false,
            reachable: false,
            rtt_ms: None,
            error_code: Some(e.code_name()),
        }),
    }
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DaemonStatusDto {
    pub running: bool,
    pub reachable: bool,
    pub rtt_ms: Option<i64>,
    // T-602: the wire `ErrorCode` name (e.g. "UNSPECIFIED"), not raw
    // display text -- the frontend looks up a translated, actionable
    // message by this key instead of rendering daemon/gRPC text
    // directly.
    pub error_code: Option<&'static str>,
}

#[tauri::command]
pub async fn get_local_state(state: State<'_, AppState>) -> CmdResult<LocalStateDto> {
    let client = require_client(&state).await?;
    client.local_state().await.map_err(CmdError::from)
}

#[tauri::command]
pub async fn list_devices(state: State<'_, AppState>) -> CmdResult<Vec<DeviceDto>> {
    let client = require_client(&state).await?;
    client.list_devices().await.map_err(CmdError::from)
}

/// Drops the local daemon's live-connection attribution for a paired
/// device (T-102's HomePanel "Disconnect" action). See
/// `LocalDaemonClient::disconnect_device` / `PeerRegistry::disconnect_device`
/// for exactly what "disconnect" means -- the device stops being
/// counted online purely because of an open SyncStream; it may still
/// show online afterward if mDNS-visible.
#[tauri::command]
pub async fn disconnect_device(state: State<'_, AppState>, device_id: String) -> CmdResult<bool> {
    let client = require_client(&state).await?;
    client
        .disconnect_device(&device_id)
        .await
        .map_err(CmdError::from)
}

/// Permanently forgets a paired device (T-307). See
/// `LocalDaemonClient::forget_device` for exactly what "forget" means
/// -- the device is removed from the paired-devices store entirely, so
/// a future reconnect requires a fresh PIN exchange.
#[tauri::command]
pub async fn forget_device(state: State<'_, AppState>, device_id: String) -> CmdResult<bool> {
    let client = require_client(&state).await?;
    client
        .forget_device(&device_id)
        .await
        .map_err(CmdError::from)
}

/// Gates whether incoming remote input is applied (T-309's
/// RemoteInputPanel toggle).
#[tauri::command]
pub async fn set_remote_input_enabled(
    state: State<'_, AppState>,
    enabled: bool,
) -> CmdResult<bool> {
    let client = require_client(&state).await?;
    client
        .set_remote_input_enabled(enabled)
        .await
        .map_err(CmdError::from)
}

/// Gates whether clipboard sync is active (T-310's tray toggle; also
/// reachable from the main window through this same command so both
/// surfaces share one underlying daemon-side flag).
#[tauri::command]
pub async fn set_clipboard_sync_enabled(
    state: State<'_, AppState>,
    enabled: bool,
) -> CmdResult<bool> {
    let client = require_client(&state).await?;
    client
        .set_clipboard_sync_enabled(enabled)
        .await
        .map_err(CmdError::from)
}

/// This machine's LAN IPv4 addresses plus the daemon port, so the Home
/// panel can show its own "connect by address" endpoint (the reverse of
/// ManualConnectDialog). Mirrors mobile's `_resolveLocalAddress`; the
/// webview can't enumerate interfaces, so the enumeration happens here
/// in native code. Empty vec means no usable LAN address was found.
#[tauri::command]
pub async fn local_addresses() -> CmdResult<LocalAddressesDto> {
    Ok(LocalAddressesDto {
        addresses: connectible_desktop_core::local::local_ipv4_addresses(),
        port: default_daemon_port(),
    })
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalAddressesDto {
    pub addresses: Vec<String>,
    pub port: u16,
}

/// The directory received files are saved to. Resolved (config override
/// -> OS Downloads -> data_dir/received) so Settings can display the
/// effective folder even before the user ever picks one. Shared with the
/// daemon through its data_dir, so this reflects exactly where the daemon
/// will write.
#[tauri::command]
pub async fn get_download_dir() -> CmdResult<String> {
    let (data_dir, _) = daemon_endpoint();
    Ok(connectibled::config::resolve_download_dir(&data_dir)
        .to_string_lossy()
        .to_string())
}

/// Persists the user's chosen received-files directory (from the Settings
/// folder picker). The daemon reads this on its next transfer, so no
/// restart or gRPC round-trip is needed. Returns the now-effective dir.
#[tauri::command]
pub async fn set_download_dir(path: String) -> CmdResult<String> {
    let (data_dir, _) = daemon_endpoint();
    connectibled::config::write_download_dir(&data_dir, std::path::Path::new(&path))
        .map_err(|e| CmdError::unspecified(format!("failed to save download directory: {e}")))?;
    Ok(connectibled::config::resolve_download_dir(&data_dir)
        .to_string_lossy()
        .to_string())
}

/// Opens a file or directory with the OS's native handler (e.g. the
/// received-files folder in the file manager, or a sent file in its
/// default app). Deliberately NOT the `opener` plugin's `open_path`:
/// on Linux that leans on a single mechanism and silently no-ops on many
/// desktop environments / minimal installs, which is exactly the "open
/// folder does nothing" bug. Instead this cascades through the common
/// openers so it works across distros and DEs (GNOME, KDE, XFCE, ...).
#[tauri::command]
pub async fn open_path(path: String) -> CmdResult<()> {
    let target = std::path::PathBuf::from(&path);
    // Run the (blocking) spawn off the async runtime's worker threads.
    tokio::task::spawn_blocking(move || open_with_os(&target))
        .await
        .map_err(|e| CmdError::unspecified(format!("open task join failed: {e}")))?
        .map_err(|e| CmdError::unspecified(format!("could not open {path}: {e}")))
}

/// Launches the first available OS opener for `path`. `spawn()` fails
/// with `NotFound` for a binary that isn't installed, so a missing
/// opener is skipped rather than fatal -- this cascade is what makes
/// "open folder" work on any Linux desktop instead of only wherever the
/// one hard-coded mechanism happens to exist.
#[cfg(target_os = "linux")]
fn open_with_os(path: &std::path::Path) -> std::io::Result<()> {
    // Most-standard first: xdg-open honours the user's configured
    // default file manager; the rest are direct fallbacks for setups
    // where xdg-utils isn't installed or has no handler registered.
    const OPENERS: &[&[&str]] = &[
        &["xdg-open"],
        &["gio", "open"],
        &["gvfs-open"],
        &["kde-open5"],
        &["kde-open"],
        &["nautilus"],
        &["dolphin"],
        &["nemo"],
        &["thunar"],
        &["pcmanfm"],
        &["caja"],
        &["gnome-open"],
    ];
    let mut last_err: Option<std::io::Error> = None;
    for opener in OPENERS {
        let mut cmd = Command::new(opener[0]);
        cmd.args(&opener[1..])
            .arg(path)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        match cmd.spawn() {
            Ok(_) => return Ok(()),
            Err(e) => last_err = Some(e),
        }
    }
    Err(last_err.unwrap_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "no file manager / opener found on this system",
        )
    }))
}

#[cfg(target_os = "macos")]
fn open_with_os(path: &std::path::Path) -> std::io::Result<()> {
    Command::new("open")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
}

#[cfg(target_os = "windows")]
fn open_with_os(path: &std::path::Path) -> std::io::Result<()> {
    Command::new("explorer")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
}

#[tauri::command]
pub async fn ping_daemon(state: State<'_, AppState>) -> CmdResult<i64> {
    let client = require_client(&state).await?;
    client.ping_rtt_ms().await.map_err(CmdError::from)
}

/// System Doctor (T-F8): runs the daemon's diagnostics engine and returns
/// the full structured report (every check + worst-severity roll-up). Pass
/// `check_id` to re-run a single check. The panel renders this directly.
#[tauri::command]
pub async fn run_diagnostics(
    state: State<'_, AppState>,
    check_id: Option<String>,
) -> CmdResult<connectible_desktop_core::dto::DiagnosticsReportDto> {
    let client = require_client(&state).await?;
    client
        .run_diagnostics(check_id.as_deref())
        .await
        .map_err(CmdError::from)
}

/// Generates a fresh pairing PIN with no requester connected yet, for
/// the desktop's "generate a pairing QR" action (Settings). The
/// frontend embeds `pinCode` directly in the QR payload -- scanning it
/// and dialing this device completes pairing with no PIN typing on
/// either side.
#[tauri::command]
pub async fn pre_arm_pairing_code(
    state: State<'_, AppState>,
) -> CmdResult<connectible_desktop_core::dto::PairingCodeDto> {
    let client = require_client(&state).await?;
    client
        .pre_arm_pairing_code()
        .await
        .map_err(CmdError::from)
}

/// Raw TCP connect to the daemon's port, no TLS/gRPC involved -- tests
/// only "is something listening here", independent of the daemon
/// actually being a working Connectible daemon (Doctor panel).
#[tauri::command]
pub async fn check_tcp_port(port: u16) -> CmdResult<bool> {
    let addr = format!("127.0.0.1:{port}");
    let outcome = tokio::time::timeout(
        std::time::Duration::from_millis(800),
        tokio::net::TcpStream::connect(&addr),
    )
    .await;
    Ok(matches!(outcome, Ok(Ok(_))))
}

/// TLS 1.3 handshake against the local daemon with no RPC call layered
/// on top -- isolates the transport/certificate layer from the
/// application layer for the Doctor panel's `tls-cert` check.
#[tauri::command]
pub async fn check_tls_handshake() -> CmdResult<()> {
    let (data_dir, port) = daemon_endpoint();
    connectible_desktop_core::local::tls_handshake_check(&data_dir, port)
        .await
        .map_err(CmdError::from)
}

/// Requester side of pairing against a nearby device (addr/port come
/// from a NearbyDevice in the local state's nearby_devices list).
#[tauri::command]
pub async fn pair_with_device(addr: String, port: u16) -> CmdResult<PairOutcome> {
    let identity = local_ui_identity();
    let (data_dir, _) = daemon_endpoint();
    let remote = RemoteDeviceClient::connect(&data_dir, &addr, port)
        .await
        .map_err(CmdError::from)?;
    remote.pair(identity).await.map_err(CmdError::from)
}

/// The responder daemon keys the pending PIN by the *requester's*
/// device_id -- i.e. this desktop's own id, the same one sent as the
/// PairRequest requester in `pair_with_device`. So confirm must submit
/// the local device_id, NOT the target device's id.
#[tauri::command]
pub async fn confirm_pin(
    state: State<'_, AppState>,
    addr: String,
    port: u16,
    pin_code: String,
    device_id: String,
) -> CmdResult<bool> {
    let identity = local_ui_identity();
    let (data_dir, _) = daemon_endpoint();
    let remote = RemoteDeviceClient::connect(&data_dir, &addr, port)
        .await
        .map_err(CmdError::from)?;
    let verified = remote
        .confirm_pin(&identity.device_id, &pin_code)
        .await
        .map_err(CmdError::from)?;
    // TOFU (T-C2): the device is now paired, so pin the cert we just saw as
    // its trust anchor (record-on-first-use). Best-effort -- a failure here
    // must not fail the pairing; the next connect backfills it anyway.
    if verified {
        if let Ok(daemon) = require_client(&state).await {
            if let Some(fp) = remote.observed_fingerprint() {
                let _ = daemon.record_fingerprint(&device_id, &fp).await;
            }
        }
    }
    Ok(verified)
}

/// Sends a file to a remote device. Progress is streamed back to the
/// frontend as "transfer-progress" events rather than returned, so the
/// UI can show a live progress bar; the command resolves with the
/// transfer_id once the transfer completes.
///
/// This upload is driven entirely by this process talking directly to
/// the *remote* peer's daemon (`RemoteDeviceClient::upload_file` below),
/// so it never touches this machine's own local daemon -- the "transfer-
/// progress" event here is the only source of progress for it. That's
/// deliberately separate from the local daemon's own `TransferProgress`
/// events on the SubscribeLocalEvents stream (forwarded to the frontend
/// as `local-event`'s `transferProgress` case, see useDaemon.ts), which
/// cover transfers where *this* daemon is the receiver.
#[tauri::command]
pub async fn send_file(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    addr: String,
    port: u16,
    file_path: String,
    device_id: String,
) -> CmdResult<String> {
    use tauri::Emitter;

    let identity = local_ui_identity();
    // TOFU (T-C3): enforce the pinned cert for this paired peer; a re-keyed
    // peer or imposter is refused with FINGERPRINT_CHANGED before any bytes.
    let daemon = require_client(&state).await?;
    let remote = connect_with_tofu(&daemon, &addr, port, &device_id).await?;

    // Deterministic (not random) so retrying the *same* file to the
    // *same* peer after a dropped connection reuses the id the receiver
    // keyed its partial file under: the new upload path resumes entirely
    // server-side (PrepareUpload reports how many bytes it already holds
    // for this file_id), so no client-side offset bookkeeping is needed.
    let transfer_id = deterministic_transfer_id(&addr, port, &file_path);
    let started_at_ms = now_ms();

    // Register the cancel handle *before* sending, so a cancel arriving
    // as soon as the first progress event reaches the UI always resolves.
    let cancel = state.register_transfer(transfer_id.clone()).await;

    let (tx, mut rx) = tokio::sync::mpsc::channel::<TransferProgressDto>(64);
    let emitter = app.clone();
    // Phase J: the last event this pump forwards is always the terminal
    // one (`remote.upload_file` sends exactly one completed/failed/
    // canceled event right before its progress sender is dropped), so
    // capturing it here is enough to record outgoing history below --
    // no separate return channel needed from `RemoteDeviceClient`.
    let last_progress = Arc::new(std::sync::Mutex::new(None::<TransferProgressDto>));
    let captured = last_progress.clone();
    let pump = tokio::spawn(async move {
        while let Some(progress) = rx.recv().await {
            *captured.lock().unwrap_or_else(|e| e.into_inner()) = Some(progress.clone());
            let _ = emitter.emit("transfer-progress", progress);
        }
    });

    let result = remote
        .upload_file(
            std::path::Path::new(&file_path),
            identity,
            tx,
            transfer_id.clone(),
            cancel,
        )
        .await
        .map_err(CmdError::from);

    state.finish_transfer(&transfer_id).await;
    let _ = pump.await;

    // Phase J (T-J4): report this outgoing send's outcome back to the
    // local daemon so it survives a restart -- this daemon otherwise
    // never observes an outgoing transfer at all (see the doc comment
    // above). Best-effort: a failure to persist history must not turn
    // an otherwise-successful (or already-failed-for-its-own-reasons)
    // send into a different error for the user.
    let terminal = last_progress.lock().unwrap_or_else(|e| e.into_inner()).clone();
    let file_name = terminal
        .as_ref()
        .map(|p| p.file_name.clone())
        .unwrap_or_else(|| {
            std::path::Path::new(&file_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("file")
                .to_string()
        });
    let total_bytes = terminal.as_ref().map(|p| p.total_bytes).unwrap_or(0);
    let status = match &terminal {
        Some(p) if p.completed => "completed",
        Some(p) if p.canceled => "canceled",
        Some(_) => "failed",
        None => {
            if result.is_ok() {
                "completed"
            } else {
                "failed"
            }
        }
    };
    if let Err(e) = daemon
        .record_transfer_history(
            &transfer_id,
            &device_id,
            &file_name,
            total_bytes,
            "outgoing",
            status,
            started_at_ms,
            now_ms(),
        )
        .await
    {
        tracing::warn!(error = %e, transfer_id = %transfer_id, "failed to persist outgoing transfer history");
    }

    result
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Phase J (T-J4): persisted transfer history for both directions,
/// most recent first.
#[tauri::command]
pub async fn list_transfer_history(
    state: State<'_, AppState>,
) -> CmdResult<Vec<connectible_desktop_core::dto::TransferHistoryEntryDto>> {
    let daemon = require_client(&state).await?;
    Ok(daemon.list_transfer_history(0).await?)
}

/// T-X14: relabels the tray menu in the active UI language and syncs the
/// clipboard-sync checkbox. The frontend (which owns the i18n locale)
/// calls this on mount, on a language switch, and whenever the
/// clipboard-sync toggle changes from any surface, so the tray is never
/// stuck in English or showing a stale checkmark. A no-op (not an error)
/// on a tray-less host where `TrayHandles` was never managed.
#[tauri::command]
pub fn update_tray(
    app: tauri::AppHandle,
    show: String,
    hide: String,
    sync_clipboard: String,
    quit: String,
    clipboard_sync_enabled: bool,
) -> CmdResult<()> {
    use tauri::Manager;
    if let Some(handles) = app.try_state::<crate::tray::TrayHandles>() {
        let _ = handles.show.set_text(&show);
        let _ = handles.hide.set_text(&hide);
        let _ = handles.clipboard_sync.set_text(&sync_clipboard);
        let _ = handles.quit.set_text(&quit);
        let _ = handles.clipboard_sync.set_checked(clipboard_sync_enabled);
    }
    Ok(())
}

/// Stable id for a (peer, file) pair so a retried send after a dropped
/// connection reuses the transfer_id the daemon's receiver kept a
/// partial file under, enabling T-025 resume. Not security-sensitive
/// (worst case of a collision is caught by the existing whole-file
/// SHA-256 verification on the receiving side), so a fast non-crypto
/// hash of address/port/path is enough -- no need to read the file
/// itself just to name the transfer.
fn deterministic_transfer_id(addr: &str, port: u16, file_path: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(addr.as_bytes());
    hasher.update(port.to_be_bytes());
    hasher.update(file_path.as_bytes());
    if let Ok(metadata) = std::fs::metadata(file_path) {
        hasher.update(metadata.len().to_be_bytes());
        if let Ok(modified) = metadata.modified() {
            if let Ok(since_epoch) = modified.duration_since(std::time::UNIX_EPOCH) {
                hasher.update(since_epoch.as_millis().to_be_bytes());
            }
        }
    }
    hex::encode(&hasher.finalize()[..16])
}

/// Aborts an in-flight outgoing transfer. No-op if it already finished.
#[tauri::command]
pub async fn cancel_transfer(state: State<'_, AppState>, transfer_id: String) -> CmdResult<()> {
    state.cancel_transfer(&transfer_id).await;
    Ok(())
}

/// Builds the outbound Identity for this desktop instance, tied to the
/// local daemon's device_id so the machine appears as one device.
fn local_ui_identity() -> connectibled::proto::connectible::v1::Identity {
    let data_dir = default_daemon_data_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let name = hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "Connectible Desktop".to_string());
    ui_identity(&data_dir, &name)
}

/// Re-exported so the events bridge can reuse the same resolution logic.
pub fn daemon_endpoint() -> (std::path::PathBuf, u16) {
    let data_dir = default_daemon_data_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    (data_dir, default_daemon_port())
}

/// Attempts to start the local daemon (connectibled) as a child process.
/// Returns the daemon status after a brief startup delay.
#[tauri::command]
pub async fn start_daemon() -> CmdResult<DaemonStatusDto> {
    // Check if already running
    let status = daemon_status().await?;
    if status.running {
        return Ok(status);
    }

    // Try to find the daemon binary
    let daemon_bin = find_daemon_binary().await?;

    let mut child = Command::new(&daemon_bin)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| CmdError::unspecified(format!("Failed to start daemon: {}", e)))?;

    // T-X8: a piped child stdout/stderr MUST be drained -- see
    // spawn_daemon_log_drains for why the daemon otherwise freezes.
    spawn_daemon_log_drains(&mut child);

    // Store the process handle
    let child_arc = Arc::new(Mutex::new(child));
    *DAEMON_PROCESS.lock().await = Some(child_arc.clone());

    // Give it a moment to start
    tokio::time::sleep(std::time::Duration::from_millis(800)).await;

    // Check status
    daemon_status().await
}

/// Stops the daemon process if we started it.
#[tauri::command]
pub async fn stop_daemon() -> CmdResult<bool> {
    let mut guard = DAEMON_PROCESS.lock().await;
    if let Some(child_arc) = guard.take() {
        let mut child = child_arc.lock().await;
        let _ = child.kill();
        let _ = child.wait();
        Ok(true)
    } else {
        Ok(false)
    }
}

/// T-X8: `start_daemon` spawns the child with piped stdout/stderr, and
/// the daemon logs at `info` to stdout (tracing fmt layer set up in
/// daemon/src/main.rs). A pipe nobody reads fills its kernel buffer
/// (~64KB on Linux), after which the daemon's next log write blocks
/// forever -- the daemon silently freezes mid-operation. So every
/// piped stream gets a dedicated drain.
///
/// Chosen fix: drain both pipes on detached threads that forward each
/// line into this app's own tracing log, rather than `Stdio::null()`.
/// Rationale: the daemon writes no log file of its own, so for a
/// UI-spawned daemon (whose stdout goes nowhere visible) these lines
/// are the only surviving diagnostics when it misbehaves; nulling them
/// would make such failures undebuggable. The threads sit blocked on
/// `read` (zero cost while the daemon is quiet) and exit on EOF when
/// the daemon terminates or `stop_daemon` kills it.
fn spawn_daemon_log_drains(child: &mut std::process::Child) {
    if let Some(stdout) = child.stdout.take() {
        std::thread::spawn(move || drain_daemon_pipe(stdout, false));
    }
    if let Some(stderr) = child.stderr.take() {
        std::thread::spawn(move || drain_daemon_pipe(stderr, true));
    }
}

/// Forwards one child pipe line-by-line into this app's tracing log.
/// Daemon stdout lines are already fully formatted tracing output
/// (timestamp/level/target), so they are re-logged verbatim under the
/// `connectibled` target rather than re-parsed; stderr (panics,
/// pre-init failures) is forwarded at `warn`.
fn drain_daemon_pipe<R: std::io::Read>(pipe: R, is_stderr: bool) {
    use std::io::{BufRead, BufReader};
    for line in BufReader::new(pipe).lines() {
        match line {
            Ok(line) => {
                if is_stderr {
                    tracing::warn!(target: "connectibled", "{line}");
                } else {
                    tracing::info!(target: "connectibled", "{line}");
                }
            }
            // A read error (EOF just ends the iterator instead): the
            // pipe is unusable, stop draining.
            Err(_) => break,
        }
    }
}

/// Tries to locate the connectibled binary.
async fn find_daemon_binary() -> CmdResult<std::path::PathBuf> {
    // 1. Check if it's in PATH
    if let Ok(output) = Command::new("which").arg("connectibled").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Ok(std::path::PathBuf::from(path));
            }
        }
    }

    // 2. Check common install locations relative to the Tauri binary
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            // Same directory
            let candidate = dir.join("connectibled");
            if candidate.exists() {
                return Ok(candidate);
            }
            // Cargo target directory (dev)
            let candidate = dir.join("../connectibled");
            if candidate.exists() {
                return Ok(candidate);
            }
        }
    }

    // 3. Check CARGO_TARGET_DIR if set
    if let Ok(target_dir) = std::env::var("CARGO_TARGET_DIR") {
        let target_path = std::path::PathBuf::from(target_dir);
        let candidate = target_path.join("debug/connectibled");
        if candidate.exists() {
            return Ok(candidate);
        }
        let candidate = target_path.join("release/connectibled");
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    // 4. Default to just "connectibled" and let the OS resolve via PATH
    Ok(std::path::PathBuf::from("connectibled"))
}

#[cfg(test)]
mod tests {
    use super::spawn_daemon_log_drains;
    use std::process::{Command, Stdio};

    /// T-X8 regression: a child writing far more than the kernel pipe
    /// buffer (~64KB) to BOTH stdout and stderr must still run to
    /// completion once the drain threads are attached. Without them the
    /// child blocks on its first write past the buffer and never exits
    /// -- exactly how a UI-spawned daemon used to freeze under
    /// RUST_LOG=debug. ~400KB per stream, well past any pipe buffer.
    #[test]
    fn drained_child_writes_past_pipe_buffer_without_blocking() {
        let line = "0123456789".repeat(10); // 100 chars + newline
        let script = format!(
            "i=0; while [ $i -lt 4096 ]; do echo {line}; echo {line} 1>&2; i=$((i+1)); done"
        );
        let mut child = Command::new("sh")
            .arg("-c")
            .arg(&script)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn sh");

        spawn_daemon_log_drains(&mut child);

        // Poll try_wait with a deadline instead of wait() so a
        // regression fails the test instead of hanging the suite.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
        loop {
            match child.try_wait().expect("try_wait") {
                Some(status) => {
                    assert!(status.success(), "drained child exited with {status}");
                    break;
                }
                None if std::time::Instant::now() > deadline => {
                    let _ = child.kill();
                    let _ = child.wait();
                    panic!("child still running after 30s -- pipes not drained (T-X8 regression)");
                }
                None => std::thread::sleep(std::time::Duration::from_millis(50)),
            }
        }
    }
}
