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

use std::time::Duration;

use common::{connect_client, spawn_test_daemon, test_identity};
use connectibled::config::Config;
use connectibled::proto::connectible::v1::upload_file_part::Part;
use connectibled::proto::connectible::v1::{
    local_event, ConfirmPinRequest, LocalEventsRequest, PairRequest, PrepareUploadRequest,
    UploadFileHeader, UploadFileMeta, UploadFilePart,
};
use sha2::{Digest, Sha256};

/// Full pair + PIN-confirm over real TLS so `device_id` is persisted as
/// paired (PrepareUpload authorizes against the paired set).
async fn pair_device(config: &Config, port: u16, device_id: &str, name: &str) {
    let mut ui = connect_client(config, port).await;
    let mut requester = connect_client(config, port).await;

    let mut events = ui
        .subscribe_local_events(LocalEventsRequest {})
        .await
        .expect("subscribe local events")
        .into_inner();

    requester
        .pair(PairRequest {
            requester: Some(test_identity(device_id, name)),
        })
        .await
        .expect("pair rpc");

    let event = tokio::time::timeout(Duration::from_secs(3), events.message())
        .await
        .expect("pairing event within 3s")
        .expect("stream healthy")
        .expect("stream not ended");
    let Some(local_event::Event::PairingRequested(prompt)) = event.event else {
        panic!("expected PairingRequested");
    };

    let confirm = requester
        .confirm_pin(ConfirmPinRequest {
            device_id: device_id.to_string(),
            pin_code: prompt.pin_code,
        })
        .await
        .expect("confirm_pin rpc")
        .into_inner();
    assert!(confirm.verified, "device must pair");
}

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
