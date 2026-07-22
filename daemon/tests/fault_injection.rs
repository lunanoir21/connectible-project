//! T-901: fault injection for a full connection drop mid-file-transfer,
//! over a REAL TLS 1.3 `SyncStream`, distinct from
//! `grpc_smoke.rs`'s `corrupted_chunk_triggers_resend_and_transfer_completes`
//! (T-306), which fault-injects a single corrupted chunk on an
//! otherwise unbroken connection. Here the whole connection is severed
//! partway through the transfer (no `is_last` chunk ever arrives on the
//! first connection), and a brand new connection is opened to resume
//! the same `transfer_id` from approximately where it left off, using
//! the existing `resume_offset_bytes` mechanism in `FileTransferStart`
//! (already covered at the unit level by
//! `daemon/src/transfer/mod.rs`'s `resumed_transfer_reuses_partial_bytes_already_on_disk`,
//! but never previously exercised end-to-end over a real socket).
//!
//! The "connection drop" is simulated by a proxy task sitting between
//! the shared `transfer::send_file` chunker and the real outbound gRPC
//! stream (the same shape `grpc_smoke.rs`'s corruption test uses): it
//! forwards frames up to the halfway point of the file, then drops
//! both ends of its channel pair instead of forwarding any more,
//! severing the request stream to the server and causing the sender's
//! next `tx.send()` to fail and return early -- exactly what a peer
//! observes when the underlying transport genuinely disappears
//! mid-stream. Nothing here depends on real network hardware; the
//! "connection" being killed is an in-process mpsc channel pair
//! standing in for the transport, per RULES.md's loopback/in-process-
//! fake requirement for fault injection tests.

mod common;

use std::time::Duration;

use common::{connect_client, spawn_test_daemon, test_identity};
use connectibled::proto::connectible::v1::sync_frame::Payload;
use connectibled::proto::connectible::v1::SyncFrame;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

/// Chunk size the daemon/sender use (`transfer::CHUNK_SIZE_BYTES`, not
/// exported since it's an implementation detail); `grpc_smoke.rs`'s own
/// fixtures already build payloads that assume this externally (see its
/// "spanning several 64KB chunks" doc comments), so relying on it here
/// is consistent with the existing test suite rather than a new
/// assumption.
const CHUNK_SIZE_BYTES: usize = 65536;

#[tokio::test]
async fn connection_drop_mid_transfer_then_resume_completes_with_correct_hash() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    // Exactly 4 chunks, so "forward the first 2, drop the rest" is an
    // exact 50% cut, matching the acceptance criterion ("kills the
    // connection at ~50% progress").
    const TOTAL_CHUNKS: usize = 4;
    const HALF_CHUNKS: usize = TOTAL_CHUNKS / 2;
    let file_size = CHUNK_SIZE_BYTES * TOTAL_CHUNKS;

    let src_dir = tempfile::tempdir().expect("src tempdir");
    let src_path = src_dir.path().join("payload.bin");
    let original: Vec<u8> = (0..file_size).map(|i| (i * 37 % 251) as u8).collect();
    std::fs::write(&src_path, &original).expect("write source file");

    let transfer_id = "t901-connection-drop".to_string();

    // ---- Phase 1: start the transfer, then sever the connection at
    // the halfway point. ----
    let mut client = connect_client(&config, port).await;
    // Capacity 1 (rather than the more generous buffering
    // `grpc_smoke.rs`'s tests use) deliberately keeps the sender and
    // the proxy in near lockstep: it means the sender genuinely
    // observes its channel close (a failed `send`) once the proxy
    // decides to stop, instead of having already buffered the whole
    // file into a slack channel before the proxy gets a chance to cut
    // it off.
    let (raw_tx, mut raw_rx) = mpsc::channel::<SyncFrame>(1);
    let (grpc_tx, grpc_rx) = mpsc::channel::<SyncFrame>(16);

    // The proxy forwards every frame until it has let through
    // HALF_CHUNKS worth of FileChunk frames, then stops -- dropping
    // both `raw_rx` (so the sender's further `raw_tx.send()` calls fail
    // and it gives up gracefully, as it would against a real dropped
    // connection) and `grpc_tx` (so the server's inbound stream ends
    // right there, exactly as if the socket had died) instead of a
    // clean is_last-terminated stream.
    let proxy = tokio::spawn(async move {
        let mut chunks_forwarded = 0usize;
        while let Some(frame) = raw_rx.recv().await {
            let is_chunk = matches!(frame.payload, Some(Payload::FileChunk(_)));
            if is_chunk && chunks_forwarded >= HALF_CHUNKS {
                // Simulate the connection dying right here: stop
                // reading (dropping raw_rx below) and stop forwarding
                // (dropping grpc_tx below), instead of continuing to
                // relay the rest of the file.
                return;
            }
            if grpc_tx.send(frame).await.is_err() {
                return;
            }
            if is_chunk {
                chunks_forwarded += 1;
            }
        }
    });

    raw_tx
        .send(SyncFrame {
            payload: Some(Payload::Identity(test_identity(
                "e2e-drop-sender",
                "E2E Drop Sender",
            ))),
        })
        .await
        .expect("send identity");

    let mut inbound = client
        .sync_stream(ReceiverStream::new(grpc_rx))
        .await
        .expect("sync_stream rpc")
        .into_inner();

    // send_file will send Identity above's chunk stream and stop
    // gracefully (Ok(())) once the proxy has severed the connection and
    // its own sends start failing -- it must NOT hang or error out.
    connectibled::transfer::send_file(&raw_tx, &src_path, transfer_id.clone(), 0)
        .await
        .expect("phase 1 partial send must return Ok even after the simulated drop");
    drop(raw_tx);

    // Drain the response stream until the server closes its side (which
    // happens once the proxy's dropped grpc_tx ends the request stream).
    while let Ok(Some(_frame)) = inbound.message().await {}
    proxy.await.expect("proxy task");

    // Give write_chunk a beat to finish writing the chunks that did
    // arrive before we inspect the on-disk partial state.
    tokio::time::sleep(Duration::from_millis(200)).await;

    let part_path = config.transfers_dir.join(format!("{transfer_id}.part"));
    let partial_on_disk = std::fs::read(&part_path)
        .expect("partial .part file must exist on disk after the connection drop");
    let expected_partial_len = CHUNK_SIZE_BYTES * HALF_CHUNKS;
    assert_eq!(
        partial_on_disk.len(),
        expected_partial_len,
        "exactly the chunks sent before the drop must have landed on disk"
    );
    assert_eq!(
        partial_on_disk,
        original[..expected_partial_len],
        "the bytes that did land must be byte-for-byte correct, not just the right length"
    );

    let dest_path = config.data_dir.join("received").join("payload.bin");
    assert!(
        !dest_path.exists(),
        "the transfer must not have finalized after only a partial connection"
    );

    // ---- Phase 2: open a brand new connection and resume the same
    // transfer_id from where phase 1 left off. ----
    let mut resume_client = connect_client(&config, port).await;
    let (resume_tx, resume_rx) = mpsc::channel::<SyncFrame>(16);

    resume_tx
        .send(SyncFrame {
            payload: Some(Payload::Identity(test_identity(
                "e2e-resume-sender",
                "E2E Resume Sender",
            ))),
        })
        .await
        .expect("send identity on the resumed connection");

    let resume_offset = expected_partial_len as i64;
    let feeder = tokio::spawn(async move {
        connectibled::transfer::send_file(&resume_tx, &src_path, transfer_id, resume_offset)
            .await
            .expect("resumed send must succeed");
        // resume_tx dropped here -> stream ends after the last chunk.
    });

    let mut resume_inbound = resume_client
        .sync_stream(ReceiverStream::new(resume_rx))
        .await
        .expect("sync_stream rpc on the resumed connection")
        .into_inner();
    while let Ok(Some(_frame)) = resume_inbound.message().await {}
    feeder.await.expect("resume feeder task");

    // Give finalize() a beat to rename the .part into place.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while !dest_path.exists() && tokio::time::Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }

    let received = std::fs::read(&dest_path)
        .expect("resumed transfer must finalize and land the completed file on disk");
    assert_eq!(
        received, original,
        "the file resumed over a brand new connection must be byte-for-byte identical \
         to the source, despite the connection drop partway through"
    );
}
