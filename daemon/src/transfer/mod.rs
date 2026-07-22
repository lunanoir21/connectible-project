use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use sha2::{Digest, Sha256};
use tokio::fs::{self, File, OpenOptions};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt, SeekFrom};
use tokio::sync::{
    broadcast,
    mpsc::{Receiver, Sender},
};

use crate::error::{DaemonError, Result};
use crate::proto::connectible::v1::sync_frame::Payload;
use crate::proto::connectible::v1::{FileChunk, FileTransferStart, SyncFrame, TransferProgress};

/// Dedicated file-upload session bookkeeping (PrepareUpload/UploadFile,
/// TASKS.md Phase A) -- separate from the chunk-over-SyncStream path.
pub mod upload;

const CHUNK_SIZE_BYTES: usize = 65536;
/// Minimum interval between two progress events for the same transfer
/// (T-027: at most ~4 UI updates per second regardless of chunk rate).
const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_millis(250);

/// Maximum number of times a single chunk offset will be resent (T-306)
/// before the requesting side gives up on it. Shared by both ends of
/// the exchange: the receiver (`TransferManager::note_corrupt_chunk`)
/// uses it to decide when to stop asking and abort with
/// `ERROR_CODE_CHECKSUM_MISMATCH` instead, and the sender
/// (`send_file_with_resend`) uses it as a defensive backstop against a
/// peer that keeps requesting the same offset.
pub const MAX_CHUNK_RESEND_ATTEMPTS: u32 = 3;

/// How long `send_file_with_resend` keeps servicing `FileChunkRequest`s
/// after it has streamed every chunk once, before deciding no further
/// resend is coming and returning. This is necessary rather than simply
/// waiting for the caller's resend channel to close: the channel is fed
/// by reading the peer's response stream, which in turn only closes
/// once this call returns and drops its outbound sender -- waiting
/// unconditionally for the channel to close would deadlock. A corrupted
/// chunk's `FileChunkRequest` normally arrives within milliseconds of
/// that chunk being sent (the receiver's CRC32 check runs inline as
/// each `FileChunk` frame is processed), so this grace period only
/// matters for a corruption on the very last chunk of the file.
const CHUNK_RESEND_GRACE_PERIOD: Duration = Duration::from_secs(2);

struct TransferMeta {
    file_name: String,
    expected_hash: String,
    part_path: PathBuf,
    total_bytes: i64,
    /// Highest contiguous byte position written so far -- resilient to
    /// duplicate chunk re-sends after a resume (max, not a sum).
    bytes_written: i64,
    last_progress_emit: Option<Instant>,
    /// Number of `FileChunkRequest`s already sent for a given
    /// `offset_bytes` (T-306), bounding retries per chunk so a
    /// systematically broken link falls back to aborting the transfer
    /// instead of looping forever (see `note_corrupt_chunk`).
    corrupt_attempts: HashMap<i64, u32>,
    /// Offsets that failed their CRC32 check and have a `FileChunkRequest`
    /// outstanding, not yet resolved by a correctly-rewritten resend
    /// (T-306). While this is non-empty, `write_chunk` must not finalize
    /// even if it has already seen the `is_last` chunk -- otherwise the
    /// assembled file would be hashed (and very likely rejected, or
    /// worse, silently short) with a hole where the corrupted chunk
    /// should be, while a resend for it is still in flight.
    pending_resend_offsets: HashSet<i64>,
    /// Set once a chunk flagged `is_last` has been successfully written.
    /// Finalization actually runs once this is true AND
    /// `pending_resend_offsets` is empty, which may be on a later chunk
    /// write than the one that set this flag (see `write_chunk`).
    finalize_pending: bool,
}

/// Receives and sends chunked file transfers over `SyncStream`
/// (T-024..T-027). One `TransferManager` is shared for the whole
/// daemon (transfer_id is a UUID, globally unique), so a transfer can
/// be resumed even if it started on a connection that has since been
/// replaced by a reconnect.
pub struct TransferManager {
    transfers_dir: PathBuf,
    in_progress: Mutex<HashMap<String, TransferMeta>>,
    /// Throttled progress feed for the local UI (T-027), consumed by
    /// SubscribeLocalEvents. No subscriber = events silently dropped.
    events: broadcast::Sender<TransferProgress>,
}

/// Outcome of writing a chunk: either the transfer continues, or the
/// final chunk landed and the whole-file hash was verified (`Finished`
/// with the destination path), the individual chunk failed its own
/// CRC32 check (`Corrupted` -- T-306: actionable, the caller should ask
/// the sender to resend just this `offset_bytes`, bounded by
/// `note_corrupt_chunk`), or the assembled file's whole-file SHA-256
/// did not match `FileTransferStart.file_hash` after every chunk
/// individually passed its own CRC32 (`WholeFileHashMismatch` -- NOT
/// actionable via a per-chunk resend: `finalize` has already deleted
/// the partial file and forgotten the transfer by the time this is
/// returned, so the caller should surface
/// `ERROR_CODE_CHECKSUM_MISMATCH` and abort, per PLAN.md edge-case
/// handling, exactly as `Corrupted` used to before T-306 split the two
/// cases apart).
pub enum ChunkOutcome {
    InProgress,
    Finished(PathBuf),
    Corrupted,
    WholeFileHashMismatch,
}

impl TransferManager {
    pub fn new(transfers_dir: PathBuf) -> Self {
        let (events, _) = broadcast::channel(64);
        Self {
            transfers_dir,
            in_progress: Mutex::new(HashMap::new()),
            events,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<TransferProgress> {
        self.events.subscribe()
    }

    /// A clone of the throttled progress broadcast sender, so the
    /// dedicated upload path (`upload::UploadWriter`) can push
    /// `TransferProgress` onto the *same* channel `SubscribeLocalEvents`
    /// already forwards to the local UI -- incoming uploads then show up
    /// in the transfers panel exactly like the old chunk path did, with
    /// no separate wiring.
    pub fn progress_sender(&self) -> broadcast::Sender<TransferProgress> {
        self.events.clone()
    }

    /// T-024/T-025: registers an incoming transfer, opening (or
    /// reusing, for a resumed transfer_id) a `.part` file on disk.
    pub async fn begin(&self, start: &FileTransferStart) -> Result<()> {
        let part_path = self
            .transfers_dir
            .join(format!("{}.part", start.transfer_id));

        // Pre-allocate/create the file without truncating -- a resumed
        // transfer_id must keep whatever bytes are already on disk so
        // re-sent chunks at earlier offsets are safe no-op overwrites
        // rather than data loss.
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(&part_path)
            .await?;
        drop(file);

        self.in_progress
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(
                start.transfer_id.clone(),
                TransferMeta {
                    file_name: start.file_name.clone(),
                    expected_hash: start.file_hash.clone(),
                    part_path,
                    total_bytes: start.file_size_bytes,
                    bytes_written: start.resume_offset_bytes.max(0),
                    last_progress_emit: None,
                    corrupt_attempts: HashMap::new(),
                    pending_resend_offsets: HashSet::new(),
                    finalize_pending: false,
                },
            );
        Ok(())
    }

    /// Records that the receiver is about to ask for `offset_bytes` of
    /// `transfer_id` to be resent (T-306), returning `true` if this
    /// request is still within `MAX_CHUNK_RESEND_ATTEMPTS` and should
    /// actually be sent, or `false` if the bound has already been
    /// reached -- in which case the caller should abort the transfer
    /// with `ERROR_CODE_CHECKSUM_MISMATCH` instead of asking again, per
    /// PLAN.md's edge-case handling for a systematically broken link.
    /// An unknown `transfer_id` (e.g. one that already finalized or was
    /// never begun) also returns `false`: there is nothing sensible to
    /// resend.
    pub fn note_corrupt_chunk(&self, transfer_id: &str, offset_bytes: i64) -> bool {
        let mut guard = self
            .in_progress
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let Some(meta) = guard.get_mut(transfer_id) else {
            return false;
        };
        let attempts = meta.corrupt_attempts.entry(offset_bytes).or_insert(0);
        if *attempts >= MAX_CHUNK_RESEND_ATTEMPTS {
            return false;
        }
        *attempts += 1;
        true
    }

    /// T-025/T-026: writes one chunk at its declared offset (seek-write,
    /// so out-of-order or duplicate chunks are idempotent), verifying
    /// the chunk's CRC32 first. On `is_last`, re-reads the assembled
    /// file to verify the whole-file SHA-256 and atomically renames it
    /// into `dest_dir` on success -- but only once every chunk that
    /// previously failed its CRC32 check has since been resent
    /// correctly (T-306: see `pending_resend_offsets` on `TransferMeta`
    /// for why finalizing on a bare `is_last` flag alone would be
    /// wrong -- an earlier offset can still be missing/stale on disk
    /// while its `FileChunkRequest` resend is in flight).
    pub async fn write_chunk(&self, chunk: &FileChunk, dest_dir: &Path) -> Result<ChunkOutcome> {
        let actual_crc = crc32fast::hash(&chunk.data);
        if actual_crc != chunk.chunk_checksum {
            let mut guard = self
                .in_progress
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if let Some(meta) = guard.get_mut(&chunk.transfer_id) {
                meta.pending_resend_offsets.insert(chunk.offset_bytes);
            }
            return Ok(ChunkOutcome::Corrupted);
        }

        let (part_path, should_finalize) = {
            let mut guard = self
                .in_progress
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let meta = guard.get_mut(&chunk.transfer_id).ok_or_else(|| {
                DaemonError::DeviceNotFound(format!("unknown transfer_id {}", chunk.transfer_id))
            })?;
            // This offset (if it had previously failed CRC32 and was
            // pending a resend) is now correctly rewritten.
            meta.pending_resend_offsets.remove(&chunk.offset_bytes);
            if chunk.is_last {
                meta.finalize_pending = true;
            }
            let should_finalize = meta.finalize_pending && meta.pending_resend_offsets.is_empty();
            (meta.part_path.clone(), should_finalize)
        };

        let mut file = OpenOptions::new().write(true).open(&part_path).await?;
        file.seek(SeekFrom::Start(chunk.offset_bytes as u64))
            .await?;
        file.write_all(&chunk.data).await?;
        file.flush().await?;

        self.record_progress(
            &chunk.transfer_id,
            chunk.offset_bytes + chunk.data.len() as i64,
        );

        if !should_finalize {
            return Ok(ChunkOutcome::InProgress);
        }

        self.finalize(&chunk.transfer_id, dest_dir).await
    }

    /// Updates the transfer's high-water mark and emits a throttled
    /// `TransferProgress` event (T-027). Intermediate events are rate
    /// limited to `PROGRESS_EMIT_INTERVAL`; terminal events (completed/
    /// failed, emitted from `finalize`) always fire.
    fn record_progress(&self, transfer_id: &str, position: i64) {
        let mut guard = self
            .in_progress
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let Some(meta) = guard.get_mut(transfer_id) else {
            return;
        };
        meta.bytes_written = meta.bytes_written.max(position);

        let now = Instant::now();
        let due = meta
            .last_progress_emit
            .is_none_or(|last| now.duration_since(last) >= PROGRESS_EMIT_INTERVAL);
        if !due {
            return;
        }
        meta.last_progress_emit = Some(now);

        let event = TransferProgress {
            transfer_id: transfer_id.to_string(),
            file_name: meta.file_name.clone(),
            bytes_transferred: meta.bytes_written,
            total_bytes: meta.total_bytes,
            completed: false,
            failed: false,
        };
        drop(guard);
        let _ = self.events.send(event);
    }

    fn emit_terminal(
        &self,
        transfer_id: &str,
        file_name: &str,
        bytes: i64,
        total: i64,
        completed: bool,
    ) {
        let _ = self.events.send(TransferProgress {
            transfer_id: transfer_id.to_string(),
            file_name: file_name.to_string(),
            bytes_transferred: bytes,
            total_bytes: total,
            completed,
            failed: !completed,
        });
    }

    async fn finalize(&self, transfer_id: &str, dest_dir: &Path) -> Result<ChunkOutcome> {
        let meta = {
            let guard = self
                .in_progress
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            guard.get(transfer_id).map(|m| {
                (
                    m.part_path.clone(),
                    m.expected_hash.clone(),
                    m.file_name.clone(),
                    m.bytes_written,
                    m.total_bytes,
                )
            })
        };
        let Some((part_path, expected_hash, file_name, bytes_written, total_bytes)) = meta else {
            return Ok(ChunkOutcome::WholeFileHashMismatch);
        };

        let actual_hash = hash_file(&part_path).await?;
        if actual_hash != expected_hash {
            let _ = fs::remove_file(&part_path).await;
            self.in_progress
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .remove(transfer_id);
            self.emit_terminal(transfer_id, &file_name, bytes_written, total_bytes, false);
            return Ok(ChunkOutcome::WholeFileHashMismatch);
        }

        fs::create_dir_all(dest_dir).await?;
        let dest_path = unique_destination(dest_dir, &file_name).await;
        move_into_place(&part_path, &dest_path).await?;
        self.in_progress
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(transfer_id);
        self.emit_terminal(transfer_id, &file_name, bytes_written, total_bytes, true);

        Ok(ChunkOutcome::Finished(dest_path))
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

/// Picks a collision-safe destination filename: `name.ext`, then
/// `name (1).ext`, `name (2).ext`, etc.
async fn unique_destination(dest_dir: &Path, file_name: &str) -> PathBuf {
    let candidate = dest_dir.join(file_name);
    if fs::metadata(&candidate).await.is_err() {
        return candidate;
    }

    let path = Path::new(file_name);
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_name);
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
    dest_dir.join(file_name) // pathological fallback, overwrite rather than loop forever
}

async fn hash_file(path: &Path) -> Result<String> {
    let mut file = File::open(path).await?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; CHUNK_SIZE_BYTES];
    loop {
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// One chunk-resend request (T-306), decoded from an inbound
/// `FileChunkRequest` frame by the caller -- `send_file_with_resend`
/// itself is transport-agnostic and only deals in plain Rust types, so
/// it has no dependency on whichever `Streaming`/gRPC client type the
/// caller reads its inbound frames from.
pub struct ResendRequest {
    pub transfer_id: String,
    pub offset_bytes: i64,
}

/// T-024: streams a file to a peer over `SyncStream` as
/// `FileTransferStart` followed by fixed-size `FileChunk` frames, each
/// carrying its own CRC32. The whole-file SHA-256 is computed via a
/// streaming hasher fed while reading, so a large file never needs to
/// be fully buffered in memory.
///
/// `start_offset` lets a caller resume a previously-interrupted send
/// (T-025): it is echoed as `resume_offset_bytes` so a receiver reusing
/// the same `transfer_id` (see `TransferManager::begin`) knows the
/// bytes before it are already on disk, and the local read cursor
/// seeks past them so they are never re-read or re-sent. Pass `0` for
/// a fresh transfer.
///
/// This is a thin wrapper around `send_file_with_resend` with no resend
/// channel, for callers that do not react to `FileChunkRequest` (e.g.
/// the existing tests below).
pub async fn send_file(
    tx: &Sender<SyncFrame>,
    path: &Path,
    transfer_id: String,
    start_offset: i64,
) -> Result<()> {
    send_file_with_resend(tx, None, path, transfer_id, start_offset).await
}

/// As `send_file`, but also services per-chunk resend requests (T-306):
/// the caller reads its own inbound `SyncStream` and forwards each
/// `FileChunkRequest` frame addressed to this transfer as a
/// `ResendRequest` on `resend_rx`. A resend reuses this call's
/// already-open file handle, seeking to the requested offset and
/// re-sending exactly that one chunk -- the same frame-construction
/// code path as a normal chunk send. Retries per offset are bounded by
/// `MAX_CHUNK_RESEND_ATTEMPTS`; further requests for an offset beyond
/// that are silently ignored (the receiver's own bound, enforced by
/// `TransferManager::note_corrupt_chunk`, is what actually ends a
/// transfer against a systematically broken link).
///
/// After every chunk has been sent once, the file handle is kept open
/// and this call keeps servicing `resend_rx` for up to
/// `CHUNK_RESEND_GRACE_PERIOD` of inactivity, since a corrupted final
/// chunk's resend request can only arrive after this point (see that
/// constant's doc for why this is a grace period rather than "wait for
/// the channel to close").
pub async fn send_file_with_resend(
    tx: &Sender<SyncFrame>,
    mut resend_rx: Option<Receiver<ResendRequest>>,
    path: &Path,
    transfer_id: String,
    start_offset: i64,
) -> Result<()> {
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file")
        .to_string();
    let metadata = fs::metadata(path).await?;
    let file_size_bytes = metadata.len() as i64;
    let mime_type = mime_guess_from_extension(path);

    let file_hash = hash_file(path).await?;
    let start_offset = start_offset.clamp(0, file_size_bytes);

    let start = SyncFrame {
        payload: Some(Payload::FileTransferStart(FileTransferStart {
            transfer_id: transfer_id.clone(),
            file_name,
            file_size_bytes,
            file_hash,
            chunk_size_bytes: CHUNK_SIZE_BYTES as u32,
            resume_offset_bytes: start_offset,
            mime_type,
        })),
    };
    if tx.send(start).await.is_err() {
        return Ok(());
    }

    let mut file = File::open(path).await?;
    if start_offset > 0 {
        file.seek(SeekFrom::Start(start_offset as u64)).await?;
    }
    let mut offset: i64 = start_offset;
    let mut buf = vec![0u8; CHUNK_SIZE_BYTES];
    let mut retry_counts: HashMap<i64, u32> = HashMap::new();

    loop {
        let n = match resend_rx.as_mut() {
            None => file.read(&mut buf).await?,
            Some(rx) => {
                tokio::select! {
                    biased;
                    req = rx.recv() => {
                        match req {
                            Some(req) if req.transfer_id == transfer_id => {
                                if try_reserve_resend_attempt(&mut retry_counts, req.offset_bytes) {
                                    resend_one_chunk(tx, &mut file, &transfer_id, req.offset_bytes, file_size_bytes).await?;
                                    // Restore the forward cursor so the
                                    // next sequential read below picks
                                    // up where the linear pass left off.
                                    file.seek(SeekFrom::Start(offset as u64)).await?;
                                }
                            }
                            Some(_unrelated_transfer) => {}
                            None => resend_rx = None,
                        }
                        continue;
                    }
                    n = file.read(&mut buf) => n?,
                }
            }
        };
        if n == 0 {
            break;
        }
        let data = buf[..n].to_vec();
        let is_last = offset + n as i64 >= file_size_bytes;
        let chunk = SyncFrame {
            payload: Some(Payload::FileChunk(FileChunk {
                transfer_id: transfer_id.clone(),
                offset_bytes: offset,
                chunk_checksum: crc32fast::hash(&data),
                data,
                is_last,
            })),
        };
        offset += n as i64;
        if tx.send(chunk).await.is_err() {
            return Ok(());
        }
    }

    // Every chunk has been sent at least once. Keep servicing resend
    // requests for a grace period in case the last chunk sent was the
    // one that turned out to be corrupted.
    if let Some(mut rx) = resend_rx {
        loop {
            match tokio::time::timeout(CHUNK_RESEND_GRACE_PERIOD, rx.recv()).await {
                Ok(Some(req)) if req.transfer_id == transfer_id => {
                    if try_reserve_resend_attempt(&mut retry_counts, req.offset_bytes) {
                        resend_one_chunk(
                            tx,
                            &mut file,
                            &transfer_id,
                            req.offset_bytes,
                            file_size_bytes,
                        )
                        .await?;
                    }
                }
                Ok(Some(_unrelated_transfer)) => {}
                Ok(None) => break, // caller closed the channel: nothing more coming
                Err(_elapsed) => break, // grace period elapsed with no request
            }
        }
    }

    Ok(())
}

/// Returns `true` (and records the attempt) if `offset_bytes` is still
/// within `MAX_CHUNK_RESEND_ATTEMPTS` for this send, `false` if the
/// sender should ignore a further request for it. This is a defensive
/// backstop on top of the receiver's own bound
/// (`TransferManager::note_corrupt_chunk`) against a peer that keeps
/// asking for the same offset.
fn try_reserve_resend_attempt(retry_counts: &mut HashMap<i64, u32>, offset_bytes: i64) -> bool {
    let attempts = retry_counts.entry(offset_bytes).or_insert(0);
    if *attempts >= MAX_CHUNK_RESEND_ATTEMPTS {
        return false;
    }
    *attempts += 1;
    true
}

/// Seeks the already-open send-side `file` to `offset_bytes` and
/// resends exactly that one chunk (T-306), using the same chunk-framing
/// logic as the linear send loop. A no-op if `offset_bytes` is out of
/// range (a malformed or stale request).
async fn resend_one_chunk(
    tx: &Sender<SyncFrame>,
    file: &mut File,
    transfer_id: &str,
    offset_bytes: i64,
    file_size_bytes: i64,
) -> Result<()> {
    if offset_bytes < 0 || offset_bytes >= file_size_bytes {
        return Ok(());
    }
    file.seek(SeekFrom::Start(offset_bytes as u64)).await?;
    let mut buf = vec![0u8; CHUNK_SIZE_BYTES];
    let n = file.read(&mut buf).await?;
    if n == 0 {
        return Ok(());
    }
    let data = buf[..n].to_vec();
    let is_last = offset_bytes + n as i64 >= file_size_bytes;
    let chunk = SyncFrame {
        payload: Some(Payload::FileChunk(FileChunk {
            transfer_id: transfer_id.to_string(),
            offset_bytes,
            chunk_checksum: crc32fast::hash(&data),
            data,
            is_last,
        })),
    };
    let _ = tx.send(chunk).await;
    Ok(())
}

fn mime_guess_from_extension(path: &Path) -> String {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
    {
        Some(ext) if ext == "txt" => "text/plain",
        Some(ext) if ext == "png" => "image/png",
        Some(ext) if ext == "jpg" || ext == "jpeg" => "image/jpeg",
        Some(ext) if ext == "pdf" => "application/pdf",
        _ => "application/octet-stream",
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_chunk(transfer_id: &str, offset: i64, data: &[u8], is_last: bool) -> FileChunk {
        FileChunk {
            transfer_id: transfer_id.to_string(),
            offset_bytes: offset,
            data: data.to_vec(),
            is_last,
            chunk_checksum: crc32fast::hash(data),
        }
    }

    async fn hash_bytes(data: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hex::encode(hasher.finalize())
    }

    #[tokio::test]
    async fn full_transfer_round_trips_and_verifies_hash() {
        let dir = tempfile::tempdir().unwrap();
        let manager = TransferManager::new(dir.path().to_path_buf());
        let dest_dir = dir.path().join("dest");

        let data = b"hello connectible world".to_vec();
        let expected_hash = hash_bytes(&data).await;

        manager
            .begin(&FileTransferStart {
                transfer_id: "t1".to_string(),
                file_name: "hello.txt".to_string(),
                file_size_bytes: data.len() as i64,
                file_hash: expected_hash,
                chunk_size_bytes: 65536,
                resume_offset_bytes: 0,
                mime_type: "text/plain".to_string(),
            })
            .await
            .expect("begin");

        let outcome = manager
            .write_chunk(&frame_chunk("t1", 0, &data, true), &dest_dir)
            .await
            .expect("write_chunk");

        match outcome {
            ChunkOutcome::Finished(path) => {
                let contents = fs::read(&path).await.expect("read finished file");
                assert_eq!(contents, data);
            }
            _ => panic!("expected Finished outcome"),
        }
    }

    #[tokio::test]
    async fn corrupted_chunk_checksum_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let manager = TransferManager::new(dir.path().to_path_buf());

        manager
            .begin(&FileTransferStart {
                transfer_id: "t2".to_string(),
                file_name: "corrupt.bin".to_string(),
                file_size_bytes: 5,
                file_hash: "irrelevant".to_string(),
                chunk_size_bytes: 65536,
                resume_offset_bytes: 0,
                mime_type: "application/octet-stream".to_string(),
            })
            .await
            .expect("begin");

        let mut chunk = frame_chunk("t2", 0, b"hello", true);
        chunk.chunk_checksum ^= 0xFFFF_FFFF; // corrupt the checksum

        let outcome = manager
            .write_chunk(&chunk, dir.path())
            .await
            .expect("write_chunk");
        assert!(matches!(outcome, ChunkOutcome::Corrupted));
    }

    #[tokio::test]
    async fn whole_file_hash_mismatch_deletes_partial_and_reports_corrupted() {
        let dir = tempfile::tempdir().unwrap();
        let manager = TransferManager::new(dir.path().to_path_buf());
        let dest_dir = dir.path().join("dest");

        manager
            .begin(&FileTransferStart {
                transfer_id: "t3".to_string(),
                file_name: "bad-hash.txt".to_string(),
                file_size_bytes: 5,
                file_hash: "0000000000000000000000000000000000000000000000000000000000000000"
                    .to_string(),
                chunk_size_bytes: 65536,
                resume_offset_bytes: 0,
                mime_type: "text/plain".to_string(),
            })
            .await
            .expect("begin");

        let outcome = manager
            .write_chunk(&frame_chunk("t3", 0, b"hello", true), &dest_dir)
            .await
            .expect("write_chunk");

        assert!(matches!(outcome, ChunkOutcome::WholeFileHashMismatch));
        assert!(
            !dir.path().join("t3.part").exists(),
            "partial file must be cleaned up"
        );
        assert!(!dest_dir.join("bad-hash.txt").exists());
    }

    #[tokio::test]
    async fn resumed_transfer_reuses_partial_bytes_already_on_disk() {
        let dir = tempfile::tempdir().unwrap();
        let manager = TransferManager::new(dir.path().to_path_buf());
        let dest_dir = dir.path().join("dest");

        let full_data = b"0123456789".to_vec();
        let expected_hash = hash_bytes(&full_data).await;

        manager
            .begin(&FileTransferStart {
                transfer_id: "t4".to_string(),
                file_name: "resume.bin".to_string(),
                file_size_bytes: full_data.len() as i64,
                file_hash: expected_hash.clone(),
                chunk_size_bytes: 65536,
                resume_offset_bytes: 0,
                mime_type: "application/octet-stream".to_string(),
            })
            .await
            .expect("begin first half");

        // First half arrives, connection drops before is_last.
        manager
            .write_chunk(&frame_chunk("t4", 0, &full_data[..5], false), &dest_dir)
            .await
            .expect("write first half");

        // "Reconnect": begin() is called again for the same transfer_id
        // (truncate=false), then only the remaining bytes are sent.
        manager
            .begin(&FileTransferStart {
                transfer_id: "t4".to_string(),
                file_name: "resume.bin".to_string(),
                file_size_bytes: full_data.len() as i64,
                file_hash: expected_hash,
                chunk_size_bytes: 65536,
                resume_offset_bytes: 5,
                mime_type: "application/octet-stream".to_string(),
            })
            .await
            .expect("begin resume");

        let outcome = manager
            .write_chunk(&frame_chunk("t4", 5, &full_data[5..], true), &dest_dir)
            .await
            .expect("write second half");

        match outcome {
            ChunkOutcome::Finished(path) => {
                let contents = fs::read(&path).await.expect("read finished file");
                assert_eq!(contents, full_data);
            }
            _ => panic!("expected Finished outcome"),
        }
    }

    #[tokio::test]
    async fn send_file_emits_start_then_chunks_with_matching_hash() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("send-me.txt");
        let data = vec![b'x'; 200_000]; // multiple 64KB-ish chunks
        fs::write(&file_path, &data).await.unwrap();

        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        send_file(&tx, &file_path, "send-1".to_string(), 0)
            .await
            .expect("send_file");
        drop(tx);

        let mut frames = Vec::new();
        while let Some(frame) = rx.recv().await {
            frames.push(frame);
        }

        let Some(Payload::FileTransferStart(start)) = frames.first().unwrap().payload.clone()
        else {
            panic!("first frame must be FileTransferStart");
        };
        assert_eq!(start.file_size_bytes, data.len() as i64);

        let mut received = Vec::new();
        let mut saw_last = false;
        for frame in &frames[1..] {
            if let Some(Payload::FileChunk(chunk)) = &frame.payload {
                received.extend_from_slice(&chunk.data);
                assert_eq!(crc32fast::hash(&chunk.data), chunk.chunk_checksum);
                if chunk.is_last {
                    saw_last = true;
                }
            }
        }
        assert!(saw_last, "exactly one chunk must be marked is_last");
        assert_eq!(received, data);
    }

    #[tokio::test]
    async fn send_file_with_start_offset_skips_already_sent_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("resume-send.txt");
        let data = vec![b'y'; 10];
        fs::write(&file_path, &data).await.unwrap();

        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        send_file(&tx, &file_path, "send-2".to_string(), 6)
            .await
            .expect("send_file");
        drop(tx);

        let mut frames = Vec::new();
        while let Some(frame) = rx.recv().await {
            frames.push(frame);
        }

        let Some(Payload::FileTransferStart(start)) = frames.first().unwrap().payload.clone()
        else {
            panic!("first frame must be FileTransferStart");
        };
        assert_eq!(start.resume_offset_bytes, 6);

        let mut received = Vec::new();
        for frame in &frames[1..] {
            if let Some(Payload::FileChunk(chunk)) = &frame.payload {
                assert_eq!(
                    chunk.offset_bytes, 6,
                    "chunk must start at the resume offset"
                );
                received.extend_from_slice(&chunk.data);
            }
        }
        assert_eq!(
            received,
            data[6..].to_vec(),
            "only the unsent tail is read/sent"
        );
    }

    /// T-306: a `ResendRequest` queued before/while the linear send loop
    /// is still running is serviced inline (the `tokio::select!` branch
    /// in the main loop), producing an extra `FileChunk` frame for the
    /// requested offset alongside the normal one.
    #[tokio::test]
    async fn send_file_with_resend_services_a_mid_stream_request() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("resend-mid.bin");
        let data: Vec<u8> = (0..10u8).collect();
        fs::write(&file_path, &data).await.unwrap();

        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        let (resend_tx, resend_rx) = tokio::sync::mpsc::channel(4);

        resend_tx
            .send(ResendRequest {
                transfer_id: "resend-1".to_string(),
                offset_bytes: 0,
            })
            .await
            .expect("queue resend request");
        drop(resend_tx);

        send_file_with_resend(&tx, Some(resend_rx), &file_path, "resend-1".to_string(), 0)
            .await
            .expect("send_file_with_resend");
        drop(tx);

        let mut chunk_frames = Vec::new();
        while let Some(frame) = rx.recv().await {
            if let Some(Payload::FileChunk(chunk)) = frame.payload {
                chunk_frames.push(chunk);
            }
        }

        assert_eq!(
            chunk_frames.len(),
            2,
            "expected the original chunk plus one resend"
        );
        assert!(chunk_frames
            .iter()
            .all(|c| c.offset_bytes == 0 && c.data == data));
    }

    /// T-306: a `ResendRequest` that arrives only after every chunk has
    /// already been sent once (the corrupted-last-chunk case) is still
    /// serviced, via the post-loop grace-period phase.
    #[tokio::test]
    async fn send_file_with_resend_services_a_request_after_the_last_chunk() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("resend-after.bin");
        let data: Vec<u8> = (0..10u8).collect();
        fs::write(&file_path, &data).await.unwrap();

        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        let (resend_tx, resend_rx) = tokio::sync::mpsc::channel(4);

        let send_task = tokio::spawn(async move {
            send_file_with_resend(&tx, Some(resend_rx), &file_path, "resend-2".to_string(), 0).await
        });

        // Drain frames until the (only) chunk has gone out, proving the
        // linear send loop has already finished before we ask for a
        // resend -- this exercises the post-loop path, distinct from
        // the mid-stream test above.
        let mut frames = Vec::new();
        loop {
            let frame = rx.recv().await.expect("start/chunk frame");
            let is_chunk = matches!(frame.payload, Some(Payload::FileChunk(_)));
            frames.push(frame);
            if is_chunk {
                break;
            }
        }

        resend_tx
            .send(ResendRequest {
                transfer_id: "resend-2".to_string(),
                offset_bytes: 0,
            })
            .await
            .expect("queue resend request");
        drop(resend_tx);

        send_task
            .await
            .expect("send task")
            .expect("send_file_with_resend");

        while let Some(frame) = rx.recv().await {
            frames.push(frame);
        }

        let chunk_frames: Vec<_> = frames
            .iter()
            .filter_map(|f| match &f.payload {
                Some(Payload::FileChunk(c)) => Some(c.clone()),
                _ => None,
            })
            .collect();
        assert_eq!(
            chunk_frames.len(),
            2,
            "original chunk plus one post-loop resend"
        );
        assert!(chunk_frames.iter().all(|c| c.data == data));
    }

    /// T-306: the sender ignores resend requests for an offset beyond
    /// `MAX_CHUNK_RESEND_ATTEMPTS`, as a defensive backstop on top of
    /// the receiver's own bound (`note_corrupt_chunk`, tested below).
    #[tokio::test]
    async fn send_file_with_resend_bounds_retries_per_offset() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("resend-bound.bin");
        let data: Vec<u8> = (0..10u8).collect();
        fs::write(&file_path, &data).await.unwrap();

        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        let (resend_tx, resend_rx) = tokio::sync::mpsc::channel(16);

        for _ in 0..(MAX_CHUNK_RESEND_ATTEMPTS + 2) {
            resend_tx
                .send(ResendRequest {
                    transfer_id: "resend-3".to_string(),
                    offset_bytes: 0,
                })
                .await
                .expect("queue resend request");
        }
        drop(resend_tx);

        send_file_with_resend(&tx, Some(resend_rx), &file_path, "resend-3".to_string(), 0)
            .await
            .expect("send_file_with_resend");
        drop(tx);

        let mut chunk_count = 0u32;
        while let Some(frame) = rx.recv().await {
            if matches!(frame.payload, Some(Payload::FileChunk(_))) {
                chunk_count += 1;
            }
        }
        assert_eq!(
            chunk_count,
            1 + MAX_CHUNK_RESEND_ATTEMPTS,
            "the original send plus exactly MAX_CHUNK_RESEND_ATTEMPTS resends, no more"
        );
    }

    /// T-306: `note_corrupt_chunk` allows exactly
    /// `MAX_CHUNK_RESEND_ATTEMPTS` requests per offset before refusing,
    /// and tracks each offset independently.
    #[tokio::test]
    async fn note_corrupt_chunk_bounds_retries_per_offset() {
        let dir = tempfile::tempdir().unwrap();
        let manager = TransferManager::new(dir.path().to_path_buf());
        manager
            .begin(&FileTransferStart {
                transfer_id: "t5".to_string(),
                file_name: "x.bin".to_string(),
                file_size_bytes: 10,
                file_hash: "irrelevant".to_string(),
                chunk_size_bytes: 65536,
                resume_offset_bytes: 0,
                mime_type: "application/octet-stream".to_string(),
            })
            .await
            .expect("begin");

        for _ in 0..MAX_CHUNK_RESEND_ATTEMPTS {
            assert!(
                manager.note_corrupt_chunk("t5", 0),
                "must allow up to the bound"
            );
        }
        assert!(
            !manager.note_corrupt_chunk("t5", 0),
            "must refuse once the bound is reached"
        );

        // A different offset on the same transfer has its own
        // independent budget.
        assert!(manager.note_corrupt_chunk("t5", 5));
    }

    #[tokio::test]
    async fn note_corrupt_chunk_refuses_unknown_transfer() {
        let manager = TransferManager::new(tempfile::tempdir().unwrap().path().to_path_buf());
        assert!(!manager.note_corrupt_chunk("does-not-exist", 0));
    }
}
