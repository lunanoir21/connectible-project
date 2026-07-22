use std::path::{Path, PathBuf};
use std::process::Command;

use x11rb::connection::Connection;

use crate::error::{DaemonError, Result};
use crate::proto::connectible::v1::MouseButton;

/// Remote input injection, abstracted so `InputDispatcher`'s
/// coalescing/rate-limiting logic (T-030) can be tested without a
/// real display server or `ydotoold` running.
pub trait InputBackend: Send + Sync {
    /// `x`, `y` are normalized `[0.0, 1.0]` coordinates, per
    /// `RemoteInputEvent`'s wire contract; the backend is responsible
    /// for converting to whatever coordinate space it needs.
    fn mouse_move(&self, x: f32, y: f32) -> Result<()>;
    fn mouse_button(&self, button: MouseButton, pressed: bool) -> Result<()>;
    fn scroll(&self, delta_x: f32, delta_y: f32) -> Result<()>;
    /// `key_code` is an X11 keysym (see RemoteInputEvent.key_code).
    fn key(&self, key_code: u32, pressed: bool) -> Result<()>;
}

fn ydotool_socket_path() -> PathBuf {
    std::env::var("YDOTOOL_SOCKET")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp/.ydotool_socket"))
}

/// T-028: X11 input backend shelling out to the `ydotool` CLI, which
/// talks to a separately-running `ydotoold` over a Unix socket (root-
/// owned uinput access, requires the udev rule documented in the
/// README). The exact `ydotool` invocation syntax has changed across
/// releases; the flags used here match the documented ydotool 0.x CLI
/// (`mousemove --absolute`, `click`, `key`) and should be re-verified
/// against whatever ydotool version ships in a given deployment.
/// Used when neither the X11 screen query nor `CONNECTIBLE_SCREEN_*`
/// env vars can determine a resolution (T-802) -- matches
/// `WaylandInputBackend::FALLBACK_OUTPUT_SIZE` so the two backends
/// degrade the same way rather than one hard-failing and the other
/// guessing.
const FALLBACK_SCREEN_SIZE: (u32, u32) = (1920, 1080);

pub struct YdotoolBackend {
    screen_width: u32,
    screen_height: u32,
}

impl YdotoolBackend {
    /// Detects a reachable `ydotoold` socket and a screen resolution to
    /// convert normalized coordinates to absolute pixels. Requires the
    /// socket (there is genuinely nothing this backend can do without
    /// it), but a resolution is not load-bearing the same way (T-802):
    /// `ydotool`'s uinput-based injection does not itself need a
    /// display server connection, only *this* coordinate-mapping step
    /// historically did. Resolution is resolved in order: (1) the X11
    /// root window, when reachable (most accurate, matches the actual
    /// XWayland/X11 output); (2) `CONNECTIBLE_SCREEN_WIDTH`/
    /// `CONNECTIBLE_SCREEN_HEIGHT` env vars, for a session with neither
    /// X11 nor a working `WaylandInputBackend` (T-302) but a known
    /// output size; (3) `FALLBACK_SCREEN_SIZE`, logged clearly so an
    /// operator can see coordinates may be mis-scaled rather than the
    /// capability silently failing to activate at all.
    pub fn new() -> Result<Self> {
        let socket = ydotool_socket_path();
        if !socket_reachable(&socket) {
            return Err(DaemonError::Input(format!(
                "ydotoold socket not found at {} -- start ydotoold and ensure the udev uinput rule is installed (see README)",
                socket.display()
            )));
        }

        let (screen_width, screen_height) = resolve_screen_size();

        Ok(Self {
            screen_width,
            screen_height,
        })
    }

    fn run(&self, args: &[&str]) -> Result<()> {
        let status = Command::new("ydotool")
            .args(args)
            .status()
            .map_err(|e| DaemonError::Input(format!("failed to invoke ydotool: {e}")))?;
        if !status.success() {
            return Err(DaemonError::Input(format!(
                "ydotool {:?} exited with {status}",
                args
            )));
        }
        Ok(())
    }
}

impl InputBackend for YdotoolBackend {
    fn mouse_move(&self, x: f32, y: f32) -> Result<()> {
        let px = (x.clamp(0.0, 1.0) * self.screen_width as f32) as i32;
        let py = (y.clamp(0.0, 1.0) * self.screen_height as f32) as i32;
        self.run(&[
            "mousemove",
            "--absolute",
            "-x",
            &px.to_string(),
            "-y",
            &py.to_string(),
        ])
    }

    fn mouse_button(&self, button: MouseButton, pressed: bool) -> Result<()> {
        // ydotool click button codes: 0x40 = left, 0x41 = right, 0x42 = middle.
        let code = match button {
            MouseButton::Left => "0x40",
            MouseButton::Right => "0x41",
            MouseButton::Middle => "0x42",
            MouseButton::Unspecified => return Ok(()),
        };
        if pressed {
            self.run(&["click", "--held", code])
        } else {
            self.run(&["click", "--held", code, "--up"])
        }
    }

    fn scroll(&self, delta_x: f32, delta_y: f32) -> Result<()> {
        self.run(&[
            "mousemove",
            "--wheel",
            "-x",
            &(delta_x as i32).to_string(),
            "-y",
            &(delta_y as i32).to_string(),
        ])
    }

    fn key(&self, key_code: u32, pressed: bool) -> Result<()> {
        let state = if pressed { 1 } else { 0 };
        self.run(&["key", &format!("{key_code}:{state}")])
    }
}

fn socket_reachable(path: &Path) -> bool {
    path.exists()
}

/// T-802: resolves a screen size for `YdotoolBackend` without treating
/// the X11 query as load-bearing for the whole backend. See
/// `YdotoolBackend::new`'s doc comment for the fallback order.
fn resolve_screen_size() -> (u32, u32) {
    if let Ok(size) = query_x11_screen_size() {
        return size;
    }

    let env_size = std::env::var("CONNECTIBLE_SCREEN_WIDTH")
        .ok()
        .and_then(|w| w.parse::<u32>().ok())
        .zip(
            std::env::var("CONNECTIBLE_SCREEN_HEIGHT")
                .ok()
                .and_then(|h| h.parse::<u32>().ok()),
        );
    if let Some(size) = env_size {
        tracing::info!(
            width = size.0,
            height = size.1,
            "no X11 connection; using CONNECTIBLE_SCREEN_WIDTH/HEIGHT for ydotool coordinate mapping"
        );
        return size;
    }

    tracing::warn!(
        width = FALLBACK_SCREEN_SIZE.0,
        height = FALLBACK_SCREEN_SIZE.1,
        "no X11 connection and no CONNECTIBLE_SCREEN_WIDTH/HEIGHT set; \
         falling back to a default resolution for ydotool coordinate \
         mapping -- absolute mouse positions may be mis-scaled on this \
         session's real output"
    );
    FALLBACK_SCREEN_SIZE
}

fn query_x11_screen_size() -> Result<(u32, u32)> {
    let (conn, screen_num) = x11rb::rust_connection::RustConnection::connect(None)
        .map_err(|e| DaemonError::Input(format!("failed to open X11 connection: {e}")))?;
    let screen = conn
        .setup()
        .roots
        .get(screen_num)
        .ok_or_else(|| DaemonError::Input("X11 screen not found".to_string()))?;
    Ok((
        screen.width_in_pixels as u32,
        screen.height_in_pixels as u32,
    ))
}

/// Returns true when this process is (most likely) running under a
/// Wayland session: `$XDG_SESSION_TYPE=wayland`, or failing that, a
/// reachable Wayland display socket (`$WAYLAND_DISPLAY`, checked the
/// same way `wayland-client` itself resolves it -- relative to
/// `$XDG_RUNTIME_DIR` unless already absolute). Duplicated from
/// `clipboard::backend`'s identical helper rather than factored into a
/// shared module -- two small, independent capability probes each
/// owning their own copy is simpler than introducing a cross-module
/// dependency for three lines of logic.
fn is_wayland_session() -> bool {
    if std::env::var("XDG_SESSION_TYPE").as_deref() == Ok("wayland") {
        return true;
    }
    let Ok(display) = std::env::var("WAYLAND_DISPLAY") else {
        return false;
    };
    let path = std::path::Path::new(&display);
    if path.is_absolute() {
        return path.exists();
    }
    match std::env::var("XDG_RUNTIME_DIR") {
        Ok(runtime_dir) => std::path::Path::new(&runtime_dir).join(&display).exists(),
        Err(_) => false,
    }
}

/// Capability probe (T-030/T-302): attempts to construct a working
/// input backend for the current session, returning `None` (rather
/// than panicking or erroring the whole daemon) when none is
/// available.
///
/// On a Wayland session, `WaylandInputBackend`
/// (wlr-virtual-pointer + virtual-keyboard) is tried first since
/// ydotool's X11-screen-size-based coordinate mapping and XTest-style
/// injection are only visible to XWayland clients; ydotool is tried
/// next (still useful for XWayland-only clients, or a non-wlroots
/// compositor lacking these protocols). On a non-Wayland session,
/// ydotool is tried directly. An explicit `tracing::warn!` documents
/// which mechanisms were attempted and why they failed, rather than
/// the daemon silently claiming a "remote_input" capability it cannot
/// deliver (see identity::capability_list).
pub fn detect_backend() -> Option<std::sync::Arc<dyn InputBackend>> {
    if is_wayland_session() {
        match super::WaylandInputBackend::new() {
            Ok(backend) => {
                tracing::info!(
                    "remote input backend: wayland-native (wlr-virtual-pointer + virtual-keyboard)"
                );
                return Some(std::sync::Arc::new(backend));
            }
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    "wayland input backend unavailable, falling back to ydotool/XWayland"
                );
            }
        }
    }

    match YdotoolBackend::new() {
        Ok(backend) => {
            tracing::info!(
                "remote input backend: ydotool/XWayland (native Wayland clients will not see injected input)"
            );
            Some(std::sync::Arc::new(backend))
        }
        Err(e) => {
            tracing::warn!(error = %e, "no remote-input backend available; remote input disabled");
            None
        }
    }
}
