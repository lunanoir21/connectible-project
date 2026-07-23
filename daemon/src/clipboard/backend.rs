use std::sync::Arc;
use std::time::Duration;

use crate::error::{DaemonError, Result};

/// One piece of clipboard content: MIME type + raw bytes (T-L2..L4).
/// Mirrors `connectible.proto`'s `ClipboardData` wire shape 1:1 (which
/// already carried `mime_type` + `bytes content` from the start --
/// "text/plain"/"image/png" per its own doc comment), so there is no
/// separate translation step between "what the OS clipboard holds" and
/// "what goes over the wire".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardContent {
    pub mime_type: String,
    pub bytes: Vec<u8>,
}

impl ClipboardContent {
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            mime_type: "text/plain".to_string(),
            bytes: text.into().into_bytes(),
        }
    }

    /// Lossy UTF-8 decode for `text/plain` content; `None` for anything
    /// else (a caller has no business treating image bytes as text).
    pub fn as_text(&self) -> Option<String> {
        (self.mime_type == "text/plain")
            .then(|| String::from_utf8_lossy(&self.bytes).into_owned())
    }
}

/// Platform clipboard read/write, abstracted so `ClipboardSync`'s
/// change-detection and echo-suppression logic (see mod.rs) can be
/// tested without a real X11/Wayland session.
pub trait ClipboardBackend: Send + Sync {
    fn get_content(&self) -> Result<Option<ClipboardContent>>;
    fn set_content(&self, content: &ClipboardContent) -> Result<()>;
}

/// T-020/T-L4: X11 clipboard backend using the `x11-clipboard` crate
/// (XFixes-aware selection reads, CLIPBOARD selection writes, INCR
/// large-transfer chunking handled internally by the crate -- verified
/// against its own `run.rs`/`lib.rs` source, since a 10MB image is well
/// past the ~256KB single-property limit most X servers enforce).
///
/// Read side (T-L4): the crate's `load`/`store` are already MIME-
/// agnostic at the atom level (X11 selections are just named-atom
/// targets; "image/png" interns as a real atom exactly like
/// "UTF8_STRING" does), so no crate limitation exists here -- this
/// backend queries the current owner's `TARGETS` list and picks the
/// first entry in `READ_TARGETS` it finds, preferring an image target
/// over a text one (a screenshot copy that also offers a text
/// fallback -- rare, but seen from some apps -- should read as the
/// image).
pub struct X11ClipboardBackend {
    clipboard: x11_clipboard::Clipboard,
}

/// `(X11 atom name, proto mime_type)`. The text atoms aren't
/// themselves valid MIME strings, hence the second column.
const READ_TARGETS: &[(&str, &str)] = &[
    ("image/png", "image/png"),
    ("UTF8_STRING", "text/plain"),
    ("text/plain", "text/plain"),
    ("STRING", "text/plain"),
];

impl X11ClipboardBackend {
    pub fn new() -> Result<Self> {
        let clipboard = x11_clipboard::Clipboard::new()
            .map_err(|e| DaemonError::Clipboard(format!("failed to open X11 connection: {e:?}")))?;
        Ok(Self { clipboard })
    }

    /// The current selection owner's advertised `TARGETS`, or empty if
    /// there is no owner (an empty clipboard -- mirrors the old
    /// `get_text`'s Timeout-means-empty handling).
    fn available_targets(&self) -> Result<Vec<x11_clipboard::Atom>> {
        let atoms = &self.clipboard.getter.atoms;
        match self.clipboard.load(
            atoms.clipboard,
            atoms.targets,
            atoms.property,
            Duration::from_millis(200),
        ) {
            Ok(bytes) => Ok(bytes
                .chunks_exact(4)
                .map(|c| {
                    x11_clipboard::Atom::from(u32::from_ne_bytes(
                        c.try_into().expect("chunks_exact(4) yields 4-byte chunks"),
                    ))
                })
                .collect()),
            Err(x11_clipboard::error::Error::Timeout) => Ok(Vec::new()),
            Err(e) => Err(DaemonError::Clipboard(format!(
                "failed to query clipboard TARGETS: {e:?}"
            ))),
        }
    }
}

impl ClipboardBackend for X11ClipboardBackend {
    fn get_content(&self) -> Result<Option<ClipboardContent>> {
        let atoms = &self.clipboard.getter.atoms;
        let available = self.available_targets()?;
        if available.is_empty() {
            return Ok(None);
        }

        for (atom_name, mime_type) in READ_TARGETS {
            let target = self.clipboard.getter.get_atom(atom_name).map_err(|e| {
                DaemonError::Clipboard(format!("failed to intern atom {atom_name}: {e:?}"))
            })?;
            if !available.contains(&target) {
                continue;
            }
            match self
                .clipboard
                .load(atoms.clipboard, target, atoms.property, Duration::from_millis(500))
            {
                Ok(bytes) if !bytes.is_empty() => {
                    return Ok(Some(ClipboardContent {
                        mime_type: (*mime_type).to_string(),
                        bytes,
                    }));
                }
                // Empty/timeout for this particular target -- try the
                // next preference rather than giving up entirely.
                Ok(_) => continue,
                Err(x11_clipboard::error::Error::Timeout) => continue,
                Err(e) => {
                    return Err(DaemonError::Clipboard(format!("clipboard read failed: {e:?}")))
                }
            }
        }
        Ok(None)
    }

    fn set_content(&self, content: &ClipboardContent) -> Result<()> {
        let atoms = &self.clipboard.getter.atoms;
        let target = if content.mime_type == "text/plain" {
            atoms.utf8_string
        } else {
            self.clipboard.getter.get_atom(&content.mime_type).map_err(|e| {
                DaemonError::Clipboard(format!(
                    "failed to intern atom {}: {e:?}",
                    content.mime_type
                ))
            })?
        };
        self.clipboard
            .store(atoms.clipboard, target, content.bytes.clone())
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
