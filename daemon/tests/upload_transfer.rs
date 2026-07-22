//! End-to-end tests for the dedicated file-upload RPCs (PrepareUpload +
//! UploadFile, TASKS.md T-A9), driven over a real TLS 1.3 connection
//! against a live `connectibled`. Covers the happy path, unpaired
//! rejection, wrong-hash rejection, and resume-after-a-dropped-stream.
//!
//! These exercise the *new* transport (bulk bytes on their own client-
//! streaming RPC, not multiplexed onto SyncStream), so unlike the older
//! chunk-path tests the sender must be paired first -- PrepareUpload
//! refuses an unpaired device before any bytes move.

mod common;

use common::{connect_client, pair_device, spawn_test_daemon, test_identity};
use connectibled::proto::connectible::v1::upload_file_part::Part;
use connectibled::proto::connectible::v1::{
    ListTransferHistoryRequest, PrepareUploadRequest, RecordTransferHistoryRequest,
    TransferHistoryEntry, UploadFileHeader, UploadFileMeta, UploadFilePart,
};
use sha2::{Digest, Sha256};

fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn header_part(session_id: &str, file_id: &str, token: &str, offset: i64) -> UploadFilePart {
    UploadFilePart {
        part: Some(Part::Header(UploadFileHeader {
            session_id: session_id.to_string(),
            file_id: file_id.to_string(),
            token: token.to_string(),
            offset_bytes: offset,
        })),
    }
}

fn chunk_part(data: &[u8]) -> UploadFilePart {
    UploadFilePart {
        part: Some(Part::Chunk(data.to_vec())),
    }
}

/// Happy path: PrepareUpload accepts a paired sender's file, then a
/// streamed UploadFile lands it verified on disk in the download dir.
#[tokio::test]
async fn upload_file_lands_on_disk_after_prepare() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-sender", "Upload Sender").await;

    let original: Vec<u8> = (0..150_000).map(|i| (i * 31 % 251) as u8).collect();
    let file_hash = sha256_hex(&original);
    let file_id = "upl-file-happy";

    let mut client = connect_client(&config, port).await;

    let prep = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-sender", "Upload Sender")),
            session_id: "sess-happy".to_string(),
            files: vec![UploadFileMeta {
                file_id: file_id.to_string(),
                file_name: "payload.bin".to_string(),
                file_size_bytes: original.len() as i64,
                file_hash: file_hash.clone(),
                mime_type: "application/octet-stream".to_string(),
            }],
        })
        .await
        .expect("prepare_upload rpc")
        .into_inner();

    assert_eq!(prep.offers.len(), 1);
    let offer = prep.offers[0].clone();
    assert!(offer.accepted, "paired sender's file is accepted");
    assert_eq!(offer.resume_offset_bytes, 0, "no partial yet");

    let session = prep.session_id.clone();
    let token = offer.token.clone();
    let data = original.clone();
    let outbound = async_stream::stream! {
        yield header_part(&session, file_id, &token, 0);
        for chunk in data.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };

    let result = client
        .upload_file(outbound)
        .await
        .expect("upload_file rpc")
        .into_inner();
    assert!(result.completed, "stream completed");
    assert!(result.hash_ok, "hash verified");
    assert_eq!(result.bytes_received, original.len() as i64);

    let dest = config.data_dir.join("received").join("payload.bin");
    let received = std::fs::read(&dest).expect("received file must exist");
    assert_eq!(received, original, "bytes match the source");
}

/// PrepareUpload refuses an unpaired sender before any bytes move.
#[tokio::test]
async fn prepare_upload_rejects_unpaired_sender() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    let mut client = connect_client(&config, port).await;

    let err = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("stranger", "Stranger")),
            session_id: "s".to_string(),
            files: vec![UploadFileMeta {
                file_id: "f".to_string(),
                file_name: "x.bin".to_string(),
                file_size_bytes: 1,
                file_hash: String::new(),
                mime_type: String::new(),
            }],
        })
        .await
        .expect_err("unpaired sender must be rejected");
    assert_eq!(err.code(), tonic::Code::Unauthenticated);
}

/// A non-positive declared size is declined at PrepareUpload time,
/// rather than being allowed to finalize on whatever bytes happen to
/// arrive (`UploadWriter::finish`'s "incomplete" guard only applies
/// when `total_bytes > 0`).
#[tokio::test]
async fn prepare_upload_rejects_non_positive_declared_size() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-badsize", "Bad Size").await;

    let mut client = connect_client(&config, port).await;
    let prep = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-badsize", "Bad Size")),
            session_id: "sess-badsize".to_string(),
            files: vec![UploadFileMeta {
                file_id: "upl-file-badsize".to_string(),
                file_name: "empty-claim.bin".to_string(),
                file_size_bytes: 0,
                file_hash: String::new(),
                mime_type: String::new(),
            }],
        })
        .await
        .expect("prepare_upload rpc")
        .into_inner();

    assert_eq!(prep.offers.len(), 1);
    let offer = &prep.offers[0];
    assert!(!offer.accepted, "a non-positive declared size must be declined");
    assert!(offer.token.is_empty(), "no token for a declined offer");
}

/// A whole-file hash that doesn't match the bytes fails verification and
/// is NOT finalized into the download dir.
#[tokio::test]
async fn upload_file_with_wrong_hash_is_not_finalized() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-badhash", "Bad Hash").await;

    let original: Vec<u8> = (0..80_000).map(|i| (i % 250) as u8).collect();
    let file_id = "upl-file-badhash";

    let mut client = connect_client(&config, port).await;
    let prep = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-badhash", "Bad Hash")),
            session_id: "sess-bad".to_string(),
            files: vec![UploadFileMeta {
                file_id: file_id.to_string(),
                file_name: "corrupt.bin".to_string(),
                file_size_bytes: original.len() as i64,
                // Deliberately wrong.
                file_hash: "00ff00ff00ff00ff".to_string(),
                mime_type: String::new(),
            }],
        })
        .await
        .expect("prepare_upload rpc")
        .into_inner();
    let offer = prep.offers[0].clone();

    let session = prep.session_id.clone();
    let token = offer.token.clone();
    let data = original.clone();
    let outbound = async_stream::stream! {
        yield header_part(&session, file_id, &token, 0);
        for chunk in data.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let result = client
        .upload_file(outbound)
        .await
        .expect("upload_file rpc")
        .into_inner();
    assert!(!result.completed, "hash mismatch is not a completion");
    assert!(!result.hash_ok);

    let dest = config.data_dir.join("received").join("corrupt.bin");
    assert!(!dest.exists(), "a hash-mismatched file must not be finalized");
}

/// Phase J / T-J2a: a completed upload and a hash-mismatched upload
/// each land as the right kind of `transfer_history` row -- proving
/// the daemon's own `upload_file` handler writes incoming history
/// directly (no RecordTransferHistory RPC involved, unlike outgoing).
#[tokio::test]
async fn upload_file_completion_and_hash_mismatch_are_recorded_in_history() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-history", "History Sender").await;
    let mut client = connect_client(&config, port).await;

    // One completed transfer.
    let good: Vec<u8> = (0..10_000).map(|i| (i % 250) as u8).collect();
    let good_hash = sha256_hex(&good);
    let good_id = "upl-history-good";
    let prep_good = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-history", "History Sender")),
            session_id: "sess-history-good".to_string(),
            files: vec![UploadFileMeta {
                file_id: good_id.to_string(),
                file_name: "good.bin".to_string(),
                file_size_bytes: good.len() as i64,
                file_hash: good_hash,
                mime_type: String::new(),
            }],
        })
        .await
        .expect("prepare_upload good")
        .into_inner();
    let offer_good = prep_good.offers[0].clone();
    let session_good = prep_good.session_id.clone();
    let token_good = offer_good.token.clone();
    let data_good = good.clone();
    let outbound_good = async_stream::stream! {
        yield header_part(&session_good, good_id, &token_good, 0);
        for chunk in data_good.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let result_good = client
        .upload_file(outbound_good)
        .await
        .expect("upload_file good")
        .into_inner();
    assert!(result_good.completed);

    // One hash-mismatched transfer.
    let bad: Vec<u8> = (0..10_000).map(|i| (i % 200) as u8).collect();
    let bad_id = "upl-history-bad";
    let prep_bad = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-history", "History Sender")),
            session_id: "sess-history-bad".to_string(),
            files: vec![UploadFileMeta {
                file_id: bad_id.to_string(),
                file_name: "bad.bin".to_string(),
                file_size_bytes: bad.len() as i64,
                file_hash: "deadbeef".to_string(),
                mime_type: String::new(),
            }],
        })
        .await
        .expect("prepare_upload bad")
        .into_inner();
    let offer_bad = prep_bad.offers[0].clone();
    let session_bad = prep_bad.session_id.clone();
    let token_bad = offer_bad.token.clone();
    let data_bad = bad.clone();
    let outbound_bad = async_stream::stream! {
        yield header_part(&session_bad, bad_id, &token_bad, 0);
        for chunk in data_bad.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let result_bad = client
        .upload_file(outbound_bad)
        .await
        .expect("upload_file bad")
        .into_inner();
    assert!(!result_bad.completed);

    let history = client
        .list_transfer_history(ListTransferHistoryRequest { limit: 50 })
        .await
        .expect("list_transfer_history rpc")
        .into_inner();

    let good_row = history
        .entries
        .iter()
        .find(|e| e.transfer_id == good_id)
        .expect("good transfer recorded");
    assert_eq!(good_row.status, "completed");
    assert_eq!(good_row.direction, "incoming");
    assert_eq!(good_row.peer_device_id, "upl-history");
    assert_eq!(good_row.file_name, "good.bin");
    assert_eq!(good_row.total_bytes, good.len() as i64);

    let bad_row = history
        .entries
        .iter()
        .find(|e| e.transfer_id == bad_id)
        .expect("bad transfer recorded");
    assert_eq!(bad_row.status, "failed");
    assert_eq!(bad_row.direction, "incoming");
}

/// Phase J / T-J2b: `RecordTransferHistory` (the desktop-reports-an-
/// outgoing-send path) round-trips through `ListTransferHistory`, and
/// is loopback-gated the same way every other local-UI RPC is.
#[tokio::test]
async fn record_transfer_history_round_trips_and_rejects_non_loopback() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    let mut client = connect_client(&config, port).await;

    client
        .record_transfer_history(RecordTransferHistoryRequest {
            entry: Some(TransferHistoryEntry {
                transfer_id: "out-1".to_string(),
                peer_device_id: "peer-desktop".to_string(),
                file_name: "notes.txt".to_string(),
                total_bytes: 42,
                direction: "outgoing".to_string(),
                status: "completed".to_string(),
                started_at_ms: 1000,
                finished_at_ms: 2000,
            }),
        })
        .await
        .expect("record_transfer_history rpc");

    let history = client
        .list_transfer_history(ListTransferHistoryRequest { limit: 10 })
        .await
        .expect("list_transfer_history rpc")
        .into_inner();
    let row = history
        .entries
        .iter()
        .find(|e| e.transfer_id == "out-1")
        .expect("outgoing entry recorded");
    assert_eq!(row.direction, "outgoing");
    assert_eq!(row.peer_device_id, "peer-desktop");
    assert_eq!(row.total_bytes, 42);

    // These test clients connect over real loopback TLS already (the
    // RPC above only succeeded because of that) -- the non-loopback
    // rejection itself is covered at the unit level in
    // grpc/service.rs's `local_rpcs_reject_non_loopback_callers`,
    // which this RPC is added to.
}

/// A stream that ends before all bytes arrive leaves a resumable partial;
/// a follow-up PrepareUpload reports the partial's length and a second
/// UploadFile from that offset completes + verifies the whole file.
#[tokio::test]
async fn upload_file_resumes_after_a_dropped_stream() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-resume", "Resume Sender").await;

    let original: Vec<u8> = (0..150_000).map(|i| (i * 17 % 251) as u8).collect();
    let file_hash = sha256_hex(&original);
    let file_id = "upl-file-resume";
    const CUT: usize = 90_000;

    let sender = || test_identity("upl-resume", "Resume Sender");
    let meta = || UploadFileMeta {
        file_id: file_id.to_string(),
        file_name: "resumable.bin".to_string(),
        file_size_bytes: original.len() as i64,
        file_hash: file_hash.clone(),
        mime_type: String::new(),
    };

    let mut client = connect_client(&config, port).await;

    // First attempt: prepare, then stream only the first CUT bytes and
    // end the stream early (simulating a dropped connection).
    let prep1 = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(sender()),
            session_id: "sess-resume".to_string(),
            files: vec![meta()],
        })
        .await
        .expect("prepare_upload 1")
        .into_inner();
    let offer1 = prep1.offers[0].clone();
    assert_eq!(offer1.resume_offset_bytes, 0);

    let s1 = prep1.session_id.clone();
    let t1 = offer1.token.clone();
    let head = original[..CUT].to_vec();
    let outbound1 = async_stream::stream! {
        yield header_part(&s1, file_id, &t1, 0);
        for chunk in head.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let r1 = client
        .upload_file(outbound1)
        .await
        .expect("upload_file 1")
        .into_inner();
    assert!(!r1.completed, "partial stream is not a completion");

    // Second attempt: prepare again -- the offer must now report the
    // partial's length as the resume offset.
    let prep2 = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(sender()),
            session_id: "sess-resume".to_string(),
            files: vec![meta()],
        })
        .await
        .expect("prepare_upload 2")
        .into_inner();
    let offer2 = prep2.offers[0].clone();
    assert_eq!(
        offer2.resume_offset_bytes, CUT as i64,
        "resume offset is the partial length"
    );

    // Stream the remaining bytes from the resume offset -> completes.
    let s2 = prep2.session_id.clone();
    let t2 = offer2.token.clone();
    let rest = original[CUT..].to_vec();
    let outbound2 = async_stream::stream! {
        yield header_part(&s2, file_id, &t2, CUT as i64);
        for chunk in rest.chunks(64 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let r2 = client
        .upload_file(outbound2)
        .await
        .expect("upload_file 2")
        .into_inner();
    assert!(r2.completed, "resumed stream completes");
    assert!(r2.hash_ok, "whole-file hash verifies across the resume seam");

    let dest = config.data_dir.join("received").join("resumable.bin");
    let received = std::fs::read(&dest).expect("received file must exist");
    assert_eq!(received, original, "resumed file matches the source exactly");
}

/// T-504 / Phase I: RULES.md's file-transfer throughput target (>=20MB/s
/// over loopback/local LAN), ported from the removed legacy chunk
/// path's `file_transfer_throughput_meets_target`
/// (`daemon/tests/grpc_smoke.rs`) onto the dedicated PrepareUpload +
/// UploadFile RPCs, now the only transfer path. Payload large enough
/// (64MB) that per-chunk overhead (gRPC framing, the streaming SHA-256)
/// actually shows up rather than being dominated by connection/TLS-
/// handshake setup cost.
///
/// The asserted floor is intentionally *far* below the 20MB/s target --
/// see the original test's removed comment (preserved in git history)
/// for why: a `cargo test` debug build's unoptimized SHA-256 runs close
/// enough to the real target on its own that gating CI on it would be
/// flaky for reasons unrelated to a genuine regression. This floor
/// still catches something like an accidental O(n^2) write path.
#[tokio::test]
async fn upload_file_throughput_meets_target() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "upl-throughput", "Throughput Sender").await;

    const SIZE_BYTES: usize = 64 * 1024 * 1024;
    const MIN_THROUGHPUT_MB_S: f64 = 5.0;

    let src_dir = tempfile::tempdir().expect("src tempdir");
    let src_path = src_dir.path().join("throughput-payload.bin");
    // Cheap-to-generate, non-degenerate content (not all-zero, so it
    // can't benefit from any accidental sparse-file/compression
    // shortcut) written via a streaming writer so *building* the
    // fixture doesn't itself dominate the measured time.
    {
        use std::io::Write;
        let mut f = std::fs::File::create(&src_path).expect("create payload file");
        let mut buf = vec![0u8; 1024 * 1024];
        let buf_len = buf.len();
        for chunk_idx in 0..(SIZE_BYTES / buf_len) {
            for (i, b) in buf.iter_mut().enumerate() {
                *b = ((chunk_idx * buf_len + i) % 251) as u8;
            }
            f.write_all(&buf).expect("write payload chunk");
        }
    }
    let original = std::fs::read(&src_path).expect("read back fixture for hashing");
    let file_hash = sha256_hex(&original);
    let file_id = "upl-throughput-file";

    let mut client = connect_client(&config, port).await;

    let start = std::time::Instant::now();

    let prep = client
        .prepare_upload(PrepareUploadRequest {
            sender: Some(test_identity("upl-throughput", "Throughput Sender")),
            session_id: "sess-throughput".to_string(),
            files: vec![UploadFileMeta {
                file_id: file_id.to_string(),
                file_name: "throughput-payload.bin".to_string(),
                file_size_bytes: original.len() as i64,
                file_hash: file_hash.clone(),
                mime_type: "application/octet-stream".to_string(),
            }],
        })
        .await
        .expect("prepare_upload rpc")
        .into_inner();
    let offer = prep.offers[0].clone();
    assert!(offer.accepted);

    let session = prep.session_id.clone();
    let token = offer.token.clone();
    let data = original.clone();
    let outbound = async_stream::stream! {
        yield header_part(&session, file_id, &token, 0);
        for chunk in data.chunks(256 * 1024) {
            yield chunk_part(chunk);
        }
    };
    let result = client
        .upload_file(outbound)
        .await
        .expect("upload_file rpc")
        .into_inner();
    let elapsed = start.elapsed();

    assert!(result.completed, "transfer must complete");
    assert!(result.hash_ok, "hash must verify");
    assert_eq!(result.bytes_received as usize, SIZE_BYTES);

    let dest = config
        .data_dir
        .join("received")
        .join("throughput-payload.bin");
    assert!(dest.exists());

    let throughput_mb_s = (SIZE_BYTES as f64 / (1024.0 * 1024.0)) / elapsed.as_secs_f64();
    eprintln!(
        "upload_file throughput: {throughput_mb_s:.1} MB/s ({SIZE_BYTES} bytes in {elapsed:?})"
    );
    assert!(
        throughput_mb_s >= MIN_THROUGHPUT_MB_S,
        "throughput {throughput_mb_s:.1} MB/s is below RULES.md's {MIN_THROUGHPUT_MB_S} MB/s target"
    );
}
