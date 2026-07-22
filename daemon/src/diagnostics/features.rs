//! Feature-backend checks (Phase F / T-F5): which display server the
//! clipboard/input backends target, whether the received-files opener and
//! input-injection tools are present, and whether stale `.part` files are
//! piling up in the transfers directory.

use std::path::Path;

use async_trait::async_trait;

use super::{Category, Check, CheckResult, DiagnosticsContext};

pub fn checks() -> Vec<Box<dyn Check>> {
    vec![
        Box::new(DisplayServer),
        Box::new(OpenerPresent),
        Box::new(InputBackend),
        Box::new(StuckPartials),
    ]
}

pub struct DisplayServer;

#[async_trait]
impl Check for DisplayServer {
    fn id(&self) -> &'static str {
        "clipboard-backend"
    }
    fn title(&self) -> &'static str {
        "Clipboard/input display server"
    }
    fn category(&self) -> Category {
        Category::Features
    }
    async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
        let x11 = std::env::var_os("DISPLAY").is_some();
        match (wayland, x11) {
            (true, _) => CheckResult::ok(self, "Wayland session")
                .with_data("session", "wayland"),
            (false, true) => CheckResult::ok(self, "X11 session").with_data("session", "x11"),
            (false, false) => CheckResult::ok(self, "No graphical session detected")
                .warn("No display server")
                .detail("Neither WAYLAND_DISPLAY nor DISPLAY is set.")
                .remediation(
                    "Clipboard and remote-input need a graphical session; run the daemon inside your desktop session.",
                ),
        }
    }
}

pub struct OpenerPresent;

#[async_trait]
impl Check for OpenerPresent {
    fn id(&self) -> &'static str {
        "file-opener"
    }
    fn title(&self) -> &'static str {
        "Received-files opener"
    }
    fn category(&self) -> Category {
        Category::Features
    }
    async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
        // Mirrors the open_path cascade (xdg-open -> gio -> a file manager).
        const OPENERS: [&str; 5] = ["xdg-open", "gio", "nautilus", "dolphin", "thunar"];
        let found: Vec<&str> = OPENERS.iter().copied().filter(|b| in_path(b)).collect();
        if found.is_empty() {
            CheckResult::ok(self, "No file opener found")
                .warn("Cannot open received files")
                .detail("None of xdg-open/gio/nautilus/dolphin/thunar are on PATH.")
                .remediation("Install xdg-utils (provides xdg-open) so 'Open' works for received files.")
        } else {
            CheckResult::ok(self, format!("Available: {}", found.join(", ")))
                .with_data("openers", found.join(","))
        }
    }
}

pub struct InputBackend;

#[async_trait]
impl Check for InputBackend {
    fn id(&self) -> &'static str {
        "input-backend"
    }
    fn title(&self) -> &'static str {
        "Remote-input injection"
    }
    fn category(&self) -> Category {
        Category::Features
    }
    async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
        // ydotool is the Wayland uinput injector; X11 uses the native
        // backend (no external binary). Report ydotool availability, which
        // is the common gap on Wayland.
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
        let ydotool = in_path("ydotool");
        if !wayland {
            CheckResult::ok(self, "Native X11 injection")
                .with_data("backend", "x11-native")
        } else if ydotool {
            CheckResult::ok(self, "ydotool available (Wayland)")
                .with_data("backend", "ydotool")
        } else {
            CheckResult::ok(self, "ydotool missing")
                .warn("Remote input may not work on Wayland")
                .detail("ydotool is not on PATH; Wayland input injection needs it.")
                .remediation("Install ydotool and ensure ydotoold is running for remote input on Wayland.")
        }
    }
}

pub struct StuckPartials;

#[async_trait]
impl Check for StuckPartials {
    fn id(&self) -> &'static str {
        "stuck-partials"
    }
    fn title(&self) -> &'static str {
        "Incomplete transfers"
    }
    fn category(&self) -> Category {
        Category::Features
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let dir = &ctx.config.transfers_dir;
        let mut count = 0usize;
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                if entry
                    .path()
                    .extension()
                    .is_some_and(|e| e.eq_ignore_ascii_case("part"))
                {
                    count += 1;
                }
            }
        }
        let base = CheckResult::ok(self, "No leftover partial files")
            .with_data("partials", count.to_string());
        if count == 0 {
            base
        } else {
            // Partials are how resume works, so a few are normal; flag only
            // as info that space may be reclaimable.
            base.warn(format!("{count} partial file(s) present"))
                .detail(format!("Resumable `.part` files in {}", dir.display()))
                .remediation("These let interrupted transfers resume; delete them to reclaim space if unwanted.")
        }
    }
}

/// True if `binary` is found on any PATH entry (a dependency-free `which`).
fn in_path(binary: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| is_executable(&dir.join(binary)))
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}
