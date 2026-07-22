//! Environment & storage checks (Phase F / T-F2): the daemon's version,
//! that its data/tls/transfers/download directories exist and are
//! writable, and that there is headroom on disk for incoming files.

use std::path::Path;

use async_trait::async_trait;

use super::{Category, Check, CheckResult, DiagnosticsContext};
use crate::config::resolve_download_dir;

/// Every environment/storage check, in report order.
pub fn checks() -> Vec<Box<dyn Check>> {
    vec![
        Box::new(DaemonVersion),
        Box::new(DirectoryWritable::data()),
        Box::new(DirectoryWritable::tls()),
        Box::new(DirectoryWritable::transfers()),
        Box::new(DownloadDirWritable),
        Box::new(DiskSpace),
    ]
}

/// Warn threshold for free disk space at the download directory: below
/// this, large incoming files are at risk.
const LOW_DISK_BYTES: u64 = 512 * 1024 * 1024; // 512 MiB

pub struct DaemonVersion;

#[async_trait]
impl Check for DaemonVersion {
    fn id(&self) -> &'static str {
        "daemon-version"
    }
    fn title(&self) -> &'static str {
        "Daemon version"
    }
    fn category(&self) -> Category {
        Category::Environment
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let version = env!("CARGO_PKG_VERSION");
        let mut result = CheckResult::ok(self, format!("connectibled {version}"))
            .with_data("version", version);
        if let Some(rt) = &ctx.runtime {
            let secs = rt.started_at.elapsed().as_secs();
            result = result
                .detail(format!("uptime {}", human_duration(secs)))
                .with_data("uptime_seconds", secs.to_string());
        }
        result
    }
}

/// Checks a configured directory exists and is writable, creating it if
/// missing (the daemon does the same at startup, so a missing dir is a
/// recoverable warn, not a hard error).
pub struct DirectoryWritable {
    id: &'static str,
    title: &'static str,
    which: Dir,
}

enum Dir {
    Data,
    Tls,
    Transfers,
}

impl DirectoryWritable {
    pub fn data() -> Self {
        Self {
            id: "data-dir-writable",
            title: "Data directory writable",
            which: Dir::Data,
        }
    }
    pub fn tls() -> Self {
        Self {
            id: "tls-dir-writable",
            title: "TLS directory writable",
            which: Dir::Tls,
        }
    }
    pub fn transfers() -> Self {
        Self {
            id: "transfers-dir-writable",
            title: "Transfers directory writable",
            which: Dir::Transfers,
        }
    }
}

#[async_trait]
impl Check for DirectoryWritable {
    fn id(&self) -> &'static str {
        self.id
    }
    fn title(&self) -> &'static str {
        self.title
    }
    fn category(&self) -> Category {
        Category::Environment
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let dir = match self.which {
            Dir::Data => &ctx.config.data_dir,
            Dir::Tls => &ctx.config.tls_dir,
            Dir::Transfers => &ctx.config.transfers_dir,
        };
        check_dir_writable(self, dir)
    }
}

pub struct DownloadDirWritable;

#[async_trait]
impl Check for DownloadDirWritable {
    fn id(&self) -> &'static str {
        "download-dir-writable"
    }
    fn title(&self) -> &'static str {
        "Download directory writable"
    }
    fn category(&self) -> Category {
        Category::Environment
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let dir = resolve_download_dir(&ctx.config.data_dir);
        check_dir_writable(self, &dir)
    }
}

pub struct DiskSpace;

#[async_trait]
impl Check for DiskSpace {
    fn id(&self) -> &'static str {
        "disk-space"
    }
    fn title(&self) -> &'static str {
        "Free disk space for incoming files"
    }
    fn category(&self) -> Category {
        Category::Environment
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let dir = resolve_download_dir(&ctx.config.data_dir);
        match free_bytes(&dir) {
            Some(free) => {
                let human = human_bytes(free);
                let base = CheckResult::ok(self, format!("{human} free"))
                    .with_data("free_bytes", free.to_string())
                    .with_data("path", dir.display().to_string());
                if free < LOW_DISK_BYTES {
                    base.warn(format!("Low free space: {human}")).remediation(
                        "Free up space on the download volume or point the download \
                         directory at one with more room.",
                    )
                } else {
                    base
                }
            }
            None => CheckResult::ok(self, "Free space unknown")
                .detail("Could not determine free space for the download volume.")
                .with_data("path", dir.display().to_string()),
        }
    }
}

fn check_dir_writable(check: &dyn Check, dir: &Path) -> CheckResult {
    // Create the dir if missing -- the daemon does this at startup, so a
    // missing one is recoverable, but flag it so the user knows it wasn't
    // there.
    let created = if dir.exists() {
        false
    } else {
        match std::fs::create_dir_all(dir) {
            Ok(()) => true,
            Err(e) => {
                return CheckResult::ok(check, "Directory missing and uncreatable")
                    .error("Directory missing and uncreatable")
                    .detail(format!("{}: {e}", dir.display()))
                    .remediation("Check the parent path exists and the daemon has permission.")
                    .with_data("path", dir.display().to_string());
            }
        }
    };

    // Probe writability with a temp file we immediately remove.
    let probe = dir.join(".connectible-doctor-write-probe");
    match std::fs::write(&probe, b"ok") {
        Ok(()) => {
            let _ = std::fs::remove_file(&probe);
            let summary = if created {
                "Directory created and writable"
            } else {
                "Directory exists and is writable"
            };
            CheckResult::ok(check, summary).with_data("path", dir.display().to_string())
        }
        Err(e) => CheckResult::ok(check, "Directory not writable")
            .error("Directory not writable")
            .detail(format!("{}: {e}", dir.display()))
            .remediation("Fix the directory's ownership/permissions so the daemon can write it.")
            .with_data("path", dir.display().to_string()),
    }
}

/// Best-effort free bytes on the filesystem holding `path`, via `df`
/// (Linux/POSIX). Returns `None` if `df` is unavailable or unparsable --
/// the check degrades to "unknown" rather than failing.
fn free_bytes(path: &Path) -> Option<u64> {
    let out = std::process::Command::new("df")
        .arg("-kP") // POSIX 1K-block output, portable columns
        .arg(path)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    // Skip the header; the data line's 4th column is available 1K-blocks.
    let line = text.lines().nth(1)?;
    let avail_blocks: u64 = line.split_whitespace().nth(3)?.parse().ok()?;
    Some(avail_blocks * 1024)
}

fn human_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

fn human_duration(secs: u64) -> String {
    let (d, h, m, s) = (secs / 86400, (secs % 86400) / 3600, (secs % 3600) / 60, secs % 60);
    if d > 0 {
        format!("{d}d {h}h {m}m")
    } else if h > 0 {
        format!("{h}h {m}m")
    } else if m > 0 {
        format!("{m}m {s}s")
    } else {
        format!("{s}s")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::diagnostics::{test_context, Status};

    #[test]
    fn human_bytes_scales_units() {
        assert_eq!(human_bytes(512), "512 B");
        assert_eq!(human_bytes(2048), "2.0 KiB");
        assert_eq!(human_bytes(5 * 1024 * 1024), "5.0 MiB");
    }

    #[tokio::test]
    async fn data_dir_writable_check_passes_for_a_real_dir() {
        // test_context() points every dir at the OS temp dir, which is
        // writable, so the directory-writable checks report ok.
        let result = DirectoryWritable::data().run(&test_context()).await;
        assert_eq!(result.status, Status::Ok);
    }

    #[tokio::test]
    async fn version_check_reports_the_crate_version() {
        let result = DaemonVersion.run(&test_context()).await;
        assert_eq!(result.status, Status::Ok);
        assert_eq!(
            result.data.get("version").map(String::as_str),
            Some(env!("CARGO_PKG_VERSION"))
        );
    }
}
