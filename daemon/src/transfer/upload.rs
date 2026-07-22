//! Upload-session bookkeeping for the dedicated file-upload RPCs
//! (`PrepareUpload`/`UploadFile`, TASKS.md Phase A / T-A4).
//!
//! Deliberately separate from the chunk-oriented [`TransferManager`](super::TransferManager):
//! the new path streams one whole file per `UploadFile` RPC straight to
//! disk, so all it needs to remember between a `PrepareUpload` and the
//! matching `UploadFile` stream is, per accepted file, an opaque token
//! tying the byte stream back to an offer plus the destination `.part`
//! path and the size/hash to verify against. Authorization (is the
//! sender paired? is receiving enabled?) is the caller's job in
//! `PrepareUpload` (T-A5); this type only mints/validates tickets.

use std::collections::HashMap;
use std::io::SeekFrom;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use tokio::fs::OpenOptions;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::sync::broadcast;

use crate::proto::connectible::v1::{TransferProgress, UploadFileMeta};

/// Everything the `UploadFile` handler (T-A6) needs once a byte stream
/// arrives, looked up by the opaque token minted in `PrepareUpload`.
#[derive(Debug, Clone)]
pub struct UploadTicket {
    pub session_id: String,
    pub file_id: String,
    pub file_name: String,
    /// The authenticated sender's `device_id` (Phase J), so a terminal
    /// outcome can be attributed to a peer in `transfer_history`
    /// without `UploadWriter`/the `upload_file` handler needing to
    /// separately look up who's connected.
    pub device_id: String,
    /// Destination partial file the stream is appended into.
    pub part_path: PathBuf,
    /// Declared final size, so the receiver knows when the stream is
    /// complete and can reject an over-long upload.
    pub total_bytes: i64,
    /// Expected whole-file SHA-256 hex (empty = skip verification).
    pub expected_hash: String,
    /// Sender-declared content type, forwarded verbatim in the terminal
    /// `TransferProgress` event so the UI can pick a file-type icon.
    pub mime_type: String,
}

/// T-security: hard ceiling on live tickets across the whole registry
/// (all peers, all sessions combined). `PrepareUpload`'s per-call file
/// cap and per-peer rate limit bound how fast this can be reached, but
/// an offer that's accepted and then never followed up with `UploadFile`
/// lingers forever (only `finish()` removes a ticket) -- across enough
/// abandoned offers over time this still needs a hard stop.
const MAX_TICKETS: usize = 10_000;

/// Tracks accepted upload offers between `PrepareUpload` and the matching
/// `UploadFile` stream. One instance per daemon, shared behind an `Arc`.
pub struct UploadRegistry {
    transfers_dir: PathBuf,
    /// Live tickets keyed by their minted token.
    tickets: Mutex<HashMap<String, UploadTicket>>,
}

impl UploadRegistry {
    pub fn new(transfers_dir: PathBuf) -> Self {
        Self {
            transfers_dir,
            tickets: Mutex::new(HashMap::new()),
        }
    }

    /// Where a given `file_id`'s partial bytes live. Keyed by the stable,
    /// deterministic `file_id` (peer+path+size+mtime) so a resumed upload
    /// reuses the exact partial a previous attempt left behind.
    ///
    /// `file_id` is client-supplied (`UploadFileMeta.file_id`), so it's
    /// sanitized to a single safe path component first -- the same
    /// traversal risk `unique_destination` guards against for
    /// `file_name`, just via a different field. Sanitizing is a pure
    /// function of the input, so a legitimate resume (same client
    /// sending the same `file_id` again) still lands on the same path.
    pub fn part_path(&self, file_id: &str) -> PathBuf {
        self.transfers_dir
            .join(format!("{}.part", super::sanitize_file_name(file_id)))
    }

    /// Bytes already on disk for this `file_id` (its `.part` length) —
    /// the offset a resumed `UploadFile` should begin at. `0` if none.
    pub fn resume_offset(&self, file_id: &str) -> i64 {
        std::fs::metadata(self.part_path(file_id))
            .map(|m| m.len() as i64)
            .unwrap_or(0)
    }

    /// Accepts one file: mints an opaque token, records its ticket, and
    /// returns `(token, resume_offset_bytes)` for the `UploadFileOffer`.
    /// Returns `None` (the offer should be reported as declined, same as
    /// "not paired"/"no disk space") once the registry is at
    /// [`MAX_TICKETS`] -- callers already have a per-offer rejection path
    /// in the proto (`UploadFileOffer.accepted`), so a full registry is
    /// surfaced the same way rather than a new error type.
    pub fn accept(&self, session_id: &str, device_id: &str, meta: &UploadFileMeta) -> Option<(String, i64)> {
        let resume_offset = self.resume_offset(&meta.file_id);
        let token = mint_token();
        let ticket = UploadTicket {
            session_id: session_id.to_string(),
            file_id: meta.file_id.clone(),
            file_name: meta.file_name.clone(),
            device_id: device_id.to_string(),
            part_path: self.part_path(&meta.file_id),
            total_bytes: meta.file_size_bytes,
            expected_hash: meta.file_hash.clone(),
            mime_type: meta.mime_type.clone(),
        };
        let mut tickets = self
            .tickets
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if tickets.len() >= MAX_TICKETS {
            return None;
        }
        tickets.insert(token.clone(), ticket);
        Some((token, resume_offset))
    }

    /// Validates an incoming `UploadFile` header against a live ticket.
    /// The token must exist and its `file_id`/`session_id` must match the
    /// header, so a byte stream can't be pointed at a file the receiver
    /// never agreed to accept. Returns a clone to drive the write; the
    /// ticket is left in place so a dropped-then-resumed stream can
    /// re-present the same token.
    pub fn resolve(&self, session_id: &str, file_id: &str, token: &str) -> Option<UploadTicket> {
        let guard = self
            .tickets
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let ticket = guard.get(token)?;
        (ticket.file_id == file_id && ticket.session_id == session_id).then(|| ticket.clone())
    }

    /// Drops a ticket once its file has finished (or been abandoned), so
    /// a spent/aborted token can't be replayed.
    pub fn finish(&self, token: &str) {
        self.tickets
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(token);
    }
}

/// Terminal outcome of an `UploadFile` stream.
#[derive(Debug)]
pub enum UploadOutcome {
    /// Every byte arrived and (if a hash was declared) it matched; the
    /// file was moved into its final destination.
    Completed { path: PathBuf, bytes: i64 },
    /// The whole-file SHA-256 did not match the declared hash; the
    /// partial was discarded (a resume would just re-fetch corruption).
    HashMismatch { bytes: i64 },
    /// The stream ended before all declared bytes arrived (dropped
    /// connection); the partial is kept on disk so a later
    /// `PrepareUpload` + `UploadFile` resumes from where it stopped.
    Incomplete { bytes: i64 },
}

/// Streams one file's bytes straight to its `.part` on disk while folding
/// a running SHA-256 -- the receive half of `UploadFile` (T-A6/T-A7/T-A8).
/// Deliberately transport-agnostic: it takes plain `&[u8]` chunks, so the
/// gRPC `Streaming<UploadFilePart>` decoding stays in the service handler
/// and this stays a pure disk/hash sink. The hash is folded as bytes are
/// written (seeded from the on-disk prefix on resume), so the file is
/// never re-read or buffered whole in memory to verify it.
pub struct UploadWriter {
    file: tokio::fs::File,
    part_path: PathBuf,
    file_name: String,
    /// Progress/UI key -- the stable `file_id`, same id the sender uses,
    /// so both ends address the transfer identically.
    transfer_id: String,
    expected_hash: String,
    total_bytes: i64,
    bytes_written: i64,
    mime_type: String,
    hasher: Sha256,
    progress: broadcast::Sender<TransferProgress>,
    last_emit: Option<Instant>,
}

impl UploadWriter {
    /// Opens (or reopens, for a resume) the ticket's `.part` positioned at
    /// `offset`, truncating anything past the agreed resume point and
    /// seeding the running hash with the bytes already on disk `[0,
    /// offset)`.
    pub async fn open(
        ticket: &UploadTicket,
        offset: i64,
        progress: broadcast::Sender<TransferProgress>,
    ) -> std::io::Result<Self> {
        let offset = offset.max(0);
        let mut file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .open(&ticket.part_path)
            .await?;
        // Drop anything beyond the resume point so a re-sent stream can't
        // leave stale trailing bytes past what it actually rewrites.
        file.set_len(offset as u64).await?;

        let mut hasher = Sha256::new();
        if offset > 0 {
            // Seed the digest with the existing prefix, read streaming so
            // even a large resume never buffers the file in RAM.
            file.seek(SeekFrom::Start(0)).await?;
            let mut remaining = offset as u64;
            let mut buf = vec![0u8; super::CHUNK_SIZE_BYTES];
            while remaining > 0 {
                let want = remaining.min(buf.len() as u64) as usize;
                let n = file.read(&mut buf[..want]).await?;
                if n == 0 {
                    break;
                }
                hasher.update(&buf[..n]);
                remaining -= n as u64;
            }
        }
        file.seek(SeekFrom::Start(offset as u64)).await?;

        Ok(Self {
            file,
            part_path: ticket.part_path.clone(),
            file_name: ticket.file_name.clone(),
            transfer_id: ticket.file_id.clone(),
            expected_hash: ticket.expected_hash.clone(),
            total_bytes: ticket.total_bytes,
            bytes_written: offset,
            mime_type: ticket.mime_type.clone(),
            hasher,
            progress,
            last_emit: None,
        })
    }

    /// Appends one chunk to disk, folds it into the hash, and emits a
    /// throttled progress event (at most one per `PROGRESS_EMIT_INTERVAL`).
    pub async fn write(&mut self, data: &[u8]) -> std::io::Result<()> {
        self.file.write_all(data).await?;
        self.hasher.update(data);
        self.bytes_written += data.len() as i64;

        let now = Instant::now();
        let due = self
            .last_emit
            .is_none_or(|last| now.duration_since(last) >= super::PROGRESS_EMIT_INTERVAL);
        if due {
            self.last_emit = Some(now);
            self.emit(false, false);
        }
        Ok(())
    }

    /// Flushes, then either finalizes into `dest_dir` (all bytes + hash
    /// match), reports a hash mismatch (partial discarded), or reports an
    /// incomplete stream (partial kept for resume).
    pub async fn finish(mut self, dest_dir: &Path) -> std::io::Result<UploadOutcome> {
        self.file.flush().await?;

        if self.total_bytes > 0 && self.bytes_written < self.total_bytes {
            // Dropped mid-stream: keep the partial, no terminal event, so
            // the next PrepareUpload resumes from bytes_written.
            return Ok(UploadOutcome::Incomplete {
                bytes: self.bytes_written,
            });
        }

        let hasher = std::mem::replace(&mut self.hasher, Sha256::new());
        let actual = hex::encode(hasher.finalize());
        if !self.expected_hash.is_empty() && actual != self.expected_hash {
            let _ = tokio::fs::remove_file(&self.part_path).await;
            self.emit(false, true);
            return Ok(UploadOutcome::HashMismatch {
                bytes: self.bytes_written,
            });
        }

        tokio::fs::create_dir_all(dest_dir).await?;
        let dest = super::unique_destination(dest_dir, &self.file_name).await;
        // rename+copy-fallback: the download dir is frequently a different
        // filesystem than transfers_dir, where a bare rename EXDEVs.
        super::move_into_place(&self.part_path, &dest).await?;
        self.emit(true, false);
        Ok(UploadOutcome::Completed {
            path: dest,
            bytes: self.bytes_written,
        })
    }

    fn emit(&self, completed: bool, failed: bool) {
        let _ = self.progress.send(TransferProgress {
            transfer_id: self.transfer_id.clone(),
            file_name: self.file_name.clone(),
            bytes_transferred: self.bytes_written,
            total_bytes: self.total_bytes,
            completed,
            failed,
            mime_type: self.mime_type.clone(),
        });
    }
}

/// 128 bits of cryptographic randomness, hex-encoded. Uses `OsRng` (like
/// PIN generation) rather than a time-seeded PRNG since the token is a
/// capability that gates writing to disk.
fn mint_token() -> String {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(file_id: &str, name: &str, size: i64, hash: &str) -> UploadFileMeta {
        UploadFileMeta {
            file_id: file_id.to_string(),
            file_name: name.to_string(),
            file_size_bytes: size,
            file_hash: hash.to_string(),
            mime_type: "application/octet-stream".to_string(),
        }
    }

    #[test]
    fn accept_mints_a_token_that_resolves_back_to_the_ticket() {
        let tmp = tempfile::tempdir().unwrap();
        let reg = UploadRegistry::new(tmp.path().to_path_buf());

        let (token, offset) = reg
            .accept("sess-1", "dev-sender", &meta("file-a", "a.bin", 100, "deadbeef"))
            .expect("under the cap");
        assert_eq!(offset, 0, "no partial on disk yet");

        let ticket = reg
            .resolve("sess-1", "file-a", &token)
            .expect("live token resolves");
        assert_eq!(ticket.file_name, "a.bin");
        assert_eq!(ticket.total_bytes, 100);
        assert_eq!(ticket.expected_hash, "deadbeef");
        assert_eq!(ticket.part_path, tmp.path().join("file-a.part"));
    }

    /// Regression test: `file_id` is client-supplied (`UploadFileMeta`),
    /// so `part_path` must sanitize it the same way `unique_destination`
    /// sanitizes `file_name` -- a malicious `file_id` claiming to escape
    /// `transfers_dir` must not actually do so.
    #[test]
    fn accept_sanitizes_a_malicious_file_id_to_stay_inside_transfers_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let reg = UploadRegistry::new(tmp.path().to_path_buf());

        let (_token, _) = reg
            .accept(
                "sess-1",
                "dev-sender",
                &meta("../../../../etc/cron.d/evil", "a.bin", 100, "deadbeef"),
            )
            .expect("under the cap");
        let part_path = reg.part_path("../../../../etc/cron.d/evil");

        assert!(
            part_path.starts_with(tmp.path()),
            "part_path {part_path:?} escaped transfers_dir {:?}",
            tmp.path()
        );
        assert_eq!(part_path, tmp.path().join("evil.part"));
    }

    #[test]
    fn accept_declines_once_the_registry_is_full() {
        let tmp = tempfile::tempdir().unwrap();
        let reg = UploadRegistry::new(tmp.path().to_path_buf());

        for i in 0..MAX_TICKETS {
            let m = meta(&format!("file-{i}"), "a.bin", 10, "");
            assert!(
                reg.accept("sess-flood", "dev-sender", &m).is_some(),
                "ticket {i} should still be under the cap"
            );
        }

        let overflow = meta("one-too-many", "a.bin", 10, "");
        assert!(
            reg.accept("sess-flood", "dev-sender", &overflow).is_none(),
            "registry must decline once MAX_TICKETS is reached"
        );
    }

    #[test]
    fn resolve_rejects_wrong_file_id_session_or_unknown_token() {
        let tmp = tempfile::tempdir().unwrap();
        let reg = UploadRegistry::new(tmp.path().to_path_buf());
        let (token, _) = reg
            .accept("sess-1", "dev-sender", &meta("file-a", "a.bin", 10, ""))
            .expect("under the cap");

        assert!(reg.resolve("sess-1", "file-b", &token).is_none(), "wrong file_id");
        assert!(reg.resolve("sess-2", "file-a", &token).is_none(), "wrong session");
        assert!(reg.resolve("sess-1", "file-a", "not-a-token").is_none(), "unknown token");
    }

    #[test]
    fn resume_offset_reflects_partial_length_and_finish_drops_the_ticket() {
        let tmp = tempfile::tempdir().unwrap();
        let reg = UploadRegistry::new(tmp.path().to_path_buf());
        // Simulate 42 bytes already received for file-a.
        std::fs::write(reg.part_path("file-a"), vec![0u8; 42]).unwrap();

        let (token, offset) = reg
            .accept("s", "dev-sender", &meta("file-a", "a.bin", 100, ""))
            .expect("under the cap");
        assert_eq!(offset, 42, "resume offset is the partial length");

        reg.finish(&token);
        assert!(reg.resolve("s", "file-a", &token).is_none(), "finished token is gone");
    }

    /// Phase I / T-I6: ported from the removed legacy chunk-path's
    /// `malicious_file_name_cannot_escape_dest_dir` (`transfer/mod.rs`),
    /// which proved this exact property through `TransferManager::begin`
    /// + `write_chunk`. `sanitize_file_name`'s own unit tests
    /// (`transfer/mod.rs`) prove the sanitizer itself is correct; this
    /// proves `UploadWriter::finish` actually calls it on the real
    /// finalize path, not just that the property holds in isolation.
    #[tokio::test]
    async fn finish_sanitizes_a_malicious_file_name_to_stay_inside_dest_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let part_path = tmp.path().join("evil.part");
        let ticket = UploadTicket {
            session_id: "sess-1".to_string(),
            file_id: "file-evil".to_string(),
            file_name: "../../../../etc/cron.d/evil".to_string(),
            device_id: "dev-sender".to_string(),
            part_path: part_path.clone(),
            total_bytes: 6,
            expected_hash: String::new(),
            mime_type: "text/plain".to_string(),
        };
        let (progress_tx, _progress_rx) = broadcast::channel(4);
        let mut writer = UploadWriter::open(&ticket, 0, progress_tx)
            .await
            .expect("open writer");
        writer.write(b"gotcha").await.expect("write");

        let dest_dir = tmp.path().join("dest");
        let outcome = writer.finish(&dest_dir).await.expect("finish");

        match outcome {
            UploadOutcome::Completed { path, .. } => {
                assert!(
                    path.starts_with(&dest_dir),
                    "finalized path {path:?} escaped dest_dir {dest_dir:?}"
                );
                assert_eq!(path.file_name().unwrap().to_str().unwrap(), "evil");
            }
            other => panic!("expected Completed outcome, got {other:?}"),
        }
    }
}
