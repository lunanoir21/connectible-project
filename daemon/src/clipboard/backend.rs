use std::sync::Arc;
use std::time::Duration;

use crate::error::{DaemonError, Result};

/// Platform clipboard read/write, abstracted so `ClipboardSync`'s
/// change-detection and echo-suppression logic (see mod.rs) can be
/// tested without a real X11/Wayland session.
pub trait ClipboardBackend: Send + Sync {
    fn get_text(&self) -> Result<Option<String>>;
    fn set_text(&self, text: &str) -> Result<()>;
}

/// T-020: X11 clipboard backend using the `x11-clipboard` crate
/// (XFixes-aware selection reads, CLIPBOARD selection writes). MVP
/// only guarantees the `text/plain` / UTF8_STRING target, per
/// connectible.proto's ClipboardData.mime_type comment.
pub struct X11ClipboardBackend {
    clipboard: x11_clipboard::Clipboard,
}

impl X11ClipboardBackend {
    pub fn new() -> Result<Self> {
        let clipboard = x11_clipboard::Clipboard::new()
            .map_err(|e| DaemonError::Clipboard(format!("failed to open X11 connection: {e:?}")))?;
        Ok(Self { clipboard })
    }
}

impl ClipboardBackend for X11ClipboardBackend {
    fn get_text(&self) -> Result<Option<String>> {
        let atoms = &self.clipboard.getter.atoms;
        match self.clipboard.load(
            atoms.clipboard,
            atoms.utf8_string,
            atoms.property,
            Duration::from_millis(200),
        ) {
            Ok(bytes) if bytes.is_empty() => Ok(None),
            Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
            // Timeout means no owner currently holds the selection (empty
            // clipboard), which is a normal state, not an error.
            Err(x11_clipboard::error::Error::Timeout) => Ok(None),
            Err(e) => Err(DaemonError::Clipboard(format!(
                "clipboard read failed: {e:?}"
            ))),
        }
    }

    fn set_text(&self, text: &str) -> Result<()> {
        let atoms = &self.clipboard.getter.atoms;
        self.clipboard
            .store(atoms.clipboard, atoms.utf8_string, text.as_bytes().to_vec())
            .map_err(|e| DaemonError::Clipboard(format!("clipboard write failed: {e:?}")))
    }
}

/// Returns true when this process is (most likely) running under a
/// Wayland session: `$XDG_SESSION_TYPE=wayland`, or failing that, a
/// reachable Wayland display socket (`$WAYLAND_DISPLAY`, checked the
/// same way `wayland-client` itself resolves it -- relative to
/// `$XDG_RUNTIME_DIR` unless already absolute).
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

/// T-021/T-301 capability probe: attempts to construct a working
/// clipboard backend for the current session, returning `None` (rather
/// than panicking or erroring the whole daemon) when none is available.
///
/// On a Wayland session, `WaylandClipboardBackend` (wlr-data-control)
/// is tried first since it works with native Wayland clients where
/// XWayland's X11 selection is invisible; the X11 backend is tried
/// next (still useful for XWayland-only clients, or a non-wlroots
/// compositor without wlr-data-control support, via XWayland). On a
/// non-Wayland session, X11 is tried directly. If nothing works, an
/// explicit `tracing::warn!` documents which mechanisms were attempted
/// and why they failed, rather than the daemon silently claiming a
/// capability it cannot deliver (see identity::capability_list).
pub fn detect_backend() -> Option<Arc<dyn ClipboardBackend>> {
    if is_wayland_session() {
        match super::WaylandClipboardBackend::new() {
            Ok(backend) => {
                tracing::info!("clipboard backend: wayland-native (wlr-data-control-unstable-v1)");
                return Some(Arc::new(backend));
            }
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    "wayland clipboard backend unavailable, falling back to X11/XWayland"
                );
            }
        }
    }

    match X11ClipboardBackend::new() {
        Ok(backend) => {
            tracing::info!(
                "clipboard backend: X11/XWayland (native Wayland clients' clipboard will not be visible)"
            );
            Some(Arc::new(backend))
        }
        Err(e) => {
            tracing::warn!(error = %e, "no clipboard backend available; clipboard sync disabled");
            None
        }
    }
}
