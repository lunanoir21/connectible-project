use std::path::{Path, PathBuf};
use std::time::Duration;

use tokio::fs;
use tokio::sync::broadcast;

use crate::proto::connectible::v1::TransferProgress;

/// Dedicated file-upload session bookkeeping (PrepareUpload/UploadFile,
/// TASKS.md Phase A) -- the only file-transfer path as of Phase I
/// (v1.0); the original chunk-over-SyncStream path this module used to
/// also implement was fully removed, see git history and
/// `TASKS-v1.0-filetransfer.md` T-A20/T-A21/T-A22 for the record.
pub mod upload;

/// Shared with `upload`: read/write buffer size for streaming file I/O.
pub(crate) const CHUNK_SIZE_BYTES: usize = 65536;
/// Minimum interval between two progress events for the same transfer
/// (T-027: at most ~4 UI updates per second regardless of chunk rate).
/// Shared with `upload::UploadWriter`.
pub(crate) const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_millis(250);

/// Broadcasts `TransferProgress` events to the local UI
/// (`SubscribeLocalEvents`). One instance is shared for the whole
/// daemon; `upload::UploadWriter` pushes onto the same channel via
/// [`TransferManager::progress_sender`] so incoming uploads show up in
/// the transfers panel with no separate wiring.
pub struct TransferManager {
    events: broadcast::Sender<TransferProgress>,
}

impl TransferManager {
    pub fn new() -> Self {
        let (events, _) = broadcast::channel(64);
        Self { events }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<TransferProgress> {
        self.events.subscribe()
    }

    /// A clone of the throttled progress broadcast sender, so the
    /// dedicated upload path (`upload::UploadWriter`) can push
    /// `TransferProgress` onto the *same* channel `SubscribeLocalEvents`
    /// already forwards to the local UI.
    pub fn progress_sender(&self) -> broadcast::Sender<TransferProgress> {
        self.events.clone()
    }
}

impl Default for TransferManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Moves a finished `.part` into its final destination, tolerating a
/// cross-filesystem move. `fs::rename` fails with `EXDEV` ("Invalid
/// cross-device link") when the source and destination are on different
/// mounts -- a very real case here, since the in-progress `.part` lives
/// in the daemon's `transfers_dir` while the finalized file goes to the
/// user's download dir, which is frequently a separate filesystem (a
/// dedicated `/home`, or `/tmp` on tmpfs). Falls back to copy+remove so
/// the transfer still completes instead of failing at the last step.
pub(crate) async fn move_into_place(src: &Path, dst: &Path) -> std::io::Result<()> {
    match fs::rename(src, dst).await {
        Ok(()) => Ok(()),
        Err(_) => {
            // Cross-device (or any other rename failure): copy the bytes
            // then drop the source. If the copy itself fails, surface that.
            fs::copy(src, dst).await?;
            let _ = fs::remove_file(src).await;
            Ok(())
        }
    }
}

/// Strips a wire-supplied file name down to a single safe path
/// component before it ever reaches a `Path::join` (T-security: a
/// sender could otherwise claim a `file_name` of `../../.bashrc` or an
/// absolute path like `/home/user/.ssh/authorized_keys` and write
/// outside `dest_dir` entirely). `Path::file_name()` already refuses to
/// return anything for `..`, `.`, or a path ending in a separator, so
/// this also covers those; anything that sanitizes away to nothing
/// falls back to a fixed name rather than ever passing the raw input
/// through.
pub(crate) fn sanitize_file_name(file_name: &str) -> String {
    Path::new(file_name)
        .file_name()
        .and_then(|s| s.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("received_file")
        .to_string()
}

/// Picks a collision-safe destination filename: `name.ext`, then
/// `name (1).ext`, `name (2).ext`, etc. `file_name` is sanitized to a
/// single path component first, so the result is always inside
/// `dest_dir` regardless of what a peer claims.
pub(crate) async fn unique_destination(dest_dir: &Path, file_name: &str) -> PathBuf {
    let file_name = sanitize_file_name(file_name);
    let candidate = dest_dir.join(&file_name);
    if fs::metadata(&candidate).await.is_err() {
        return candidate;
    }

    let path = Path::new(&file_name);
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(&file_name);
    let ext = path.extension().and_then(|s| s.to_str());

    for i in 1..10_000 {
        let name = match ext {
            Some(ext) => format!("{stem} ({i}).{ext}"),
            None => format!("{stem} ({i})"),
        };
        let candidate = dest_dir.join(name);
        if fs::metadata(&candidate).await.is_err() {
            return candidate;
        }
    }
    dest_dir.join(&file_name) // pathological fallback, overwrite rather than loop forever
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_file_name_strips_relative_traversal() {
        assert_eq!(sanitize_file_name("../../etc/cron.d/evil"), "evil");
        assert_eq!(sanitize_file_name("../../../.bashrc"), ".bashrc");
    }

    #[test]
    fn sanitize_file_name_strips_absolute_paths() {
        assert_eq!(
            sanitize_file_name("/home/user/.ssh/authorized_keys"),
            "authorized_keys"
        );
    }

    #[test]
    fn sanitize_file_name_falls_back_on_a_pure_traversal_component() {
        // `Path::file_name()` returns None for "..", ".", or an empty
        // string -- must not silently become empty. A trailing slash
        // ("a/b/") still yields "b", which is fine: it's just the last
        // component, not a traversal.
        assert_eq!(sanitize_file_name(".."), "received_file");
        assert_eq!(sanitize_file_name("."), "received_file");
        assert_eq!(sanitize_file_name(""), "received_file");
        assert_eq!(sanitize_file_name("a/b/"), "b");
    }

    #[test]
    fn sanitize_file_name_leaves_a_plain_name_untouched() {
        assert_eq!(sanitize_file_name("vacation-photo.jpg"), "vacation-photo.jpg");
    }
}
