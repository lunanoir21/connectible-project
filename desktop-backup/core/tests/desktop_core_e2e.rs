//! End-to-end tests for the desktop core against a real in-process
//! daemon (real TLS 1.3 listener, real SQLite, real transfer engine).
//! These are the desktop equivalents of the daemon's grpc_smoke tests
//! and prove the exact client paths the Tauri shell will use.

use std::sync::Arc;
use std::time::Duration;

use connectible_desktop_core::remote::new_transfer_id;
use connectible_desktop_core::{LocalDaemonClient, RemoteDeviceClient};
use connectibled::config::Config;
use connectibled::proto::connectible::v1::Identity;
use sha2::{Digest, Sha256};
use tokio::sync::Notify;

fn free_port() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener.local_addr().expect("local addr").port()
}

fn ui_identity() -> Identity {
    Identity {
        device_id: "desktop-ui-test".to_string(),
        device_name: "Desktop UI Test".to_string(),
        platform: 0,
        device_type: 0,
        protocol_version: 1,
        app_version: "0.1.0".to_string(),
        capabilities: vec![],
    }
}

async fn spawn_test_daemon() -> (tempfile::TempDir, Config, u16) {
    let tmp = tempfile::tempdir().expect("tempdir");
    let data_dir = tmp.path().to_path_buf();
    let port = free_port();

    let config = Config {
        data_dir: data_dir.clone(),
        tls_dir: data_dir.join("tls"),
        transfers_dir: data_dir.join("transfers"),
        db_path: data_dir.join("connectibled.db"),
        grpc_port: port,
        device_name: "Desktop-Core-Test-Daemon".to_string(),
    };
    std::fs::create_dir_all(&config.tls_dir).expect("create tls dir");
    std::fs::create_dir_all(&config.transfers_dir).expect("create transfers dir");
    // Pin received files to the temp data_dir so the test stays hermetic:
    // production defaults the download dir to the OS Downloads folder, and
    // a test must never write payloads into the real ~/Downloads. Keeps
    // the historical data_dir/received location the transfer assertion
    // below expects.
    connectibled::config::write_download_dir(&data_dir, &data_dir.join("received"))
        .expect("pin test download dir");

    // Own OS thread + own runtime, mirroring production process
    // separation (same pattern as the daemon's grpc_smoke tests).
    let run_config = config.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().expect("build daemon runtime");
        rt.block_on(async move {
            let _ = connectibled::run(run_config).await;
        });
    });

    tokio::time::sleep(Duration::from_millis(300)).await;
    (tmp, config, port)
}

#[tokio::test]
async fn local_client_pings_and_reads_state_with_pinned_cert() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let client = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("connect with cert pinned from daemon data dir");

    let rtt = client.ping_rtt_ms().await.expect("ping");
    assert!(rtt >= 0);

    let state = client
        .local_state()
        .await
        .expect("local state (loopback allowed)");
    assert!(!state.device_id.is_empty());
    assert!(state.capabilities.contains(&"file_transfer".to_string()));

    let devices = client.list_devices().await.expect("list devices");
    assert!(devices.is_empty(), "fresh daemon has no paired devices");
}

/// Full requester-side pairing driven through RemoteDeviceClient with
/// the accept-self-signed verifier: exactly what the desktop app does
/// when the user clicks "pair" on a nearby device. The PIN is read via
/// the local event stream, as the *responder's* UI would show it.
#[tokio::test]
async fn remote_client_pairs_using_pin_from_local_event_stream() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let ui = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("local client");
    let mut events = ui.subscribe_local_events().await.expect("subscribe");

    let remote = RemoteDeviceClient::connect("127.0.0.1", port)
        .await
        .expect("connect with accept-self-signed verifier");

    let outcome = remote.pair(ui_identity()).await.expect("pair rpc");
    assert!(outcome.accepted);
    assert!(outcome.pin_expires_at_ms > 0);

    let event = tokio::time::timeout(Duration::from_secs(3), events.message())
        .await
        .expect("event within 3s")
        .expect("stream healthy")
        .expect("stream open");
    let Some(connectibled::proto::connectible::v1::local_event::Event::PairingRequested(prompt)) =
        event.event
    else {
        panic!("expected PairingRequested local event");
    };

    let verified = remote
        .confirm_pin("desktop-ui-test", &prompt.pin_code)
        .await
        .expect("confirm_pin rpc");
    assert!(verified);

    let devices = ui.list_devices().await.expect("list devices");
    assert!(devices.iter().any(|d| d.device_id == "desktop-ui-test"));
}

#[tokio::test]
async fn send_file_delivers_intact_file_and_reports_progress() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let source_dir = tempfile::tempdir().expect("source dir");
    let source_path = source_dir.path().join("payload.bin");
    let payload = vec![0xABu8; 300_000]; // several 64KB chunks
    std::fs::write(&source_path, &payload).expect("write source file");

    let remote = RemoteDeviceClient::connect("127.0.0.1", port)
        .await
        .expect("remote connect");

    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(64);
    remote
        .send_file(
            &source_path,
            ui_identity(),
            progress_tx,
            new_transfer_id(),
            Arc::new(Notify::new()),
            0,
        )
        .await
        .expect("send_file");

    let mut saw_completed = false;
    let mut last_bytes = 0;
    while let Some(progress) = progress_rx.recv().await {
        assert_eq!(progress.direction, "outgoing");
        assert!(
            progress.bytes_transferred >= last_bytes,
            "progress must be monotonic"
        );
        last_bytes = progress.bytes_transferred;
        if progress.completed {
            saw_completed = true;
        }
    }
    assert!(
        saw_completed,
        "final progress event must be marked completed"
    );
    assert_eq!(last_bytes, payload.len() as i64);

    // The daemon finalizes received files under <data_dir>/received.
    let received_path = config.data_dir.join("received").join("payload.bin");
    let received = std::fs::read(&received_path).expect("received file exists");
    let mut expected_hasher = Sha256::new();
    expected_hasher.update(&payload);
    let mut actual_hasher = Sha256::new();
    actual_hasher.update(&received);
    assert_eq!(
        hex::encode(actual_hasher.finalize()),
        hex::encode(expected_hasher.finalize()),
        "received file must be byte-identical"
    );
}

/// The dedicated upload path (PrepareUpload + UploadFile) end to end:
/// pair first (the new path requires a paired sender), then upload a file
/// and assert it lands verified on disk with monotonic outgoing progress.
/// Resume/cancel/wrong-hash are exercised daemon-side in
/// `daemon/tests/upload_transfer.rs`; this proves the desktop client half.
#[tokio::test]
async fn upload_file_delivers_intact_file_and_reports_progress() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    // Pair the desktop identity so PrepareUpload authorizes it.
    let ui = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("local client");
    let mut events = ui.subscribe_local_events().await.expect("subscribe");
    let remote = RemoteDeviceClient::connect("127.0.0.1", port)
        .await
        .expect("remote connect");
    remote.pair(ui_identity()).await.expect("pair rpc");
    let event = tokio::time::timeout(Duration::from_secs(3), events.message())
        .await
        .expect("event within 3s")
        .expect("stream healthy")
        .expect("stream open");
    let Some(connectibled::proto::connectible::v1::local_event::Event::PairingRequested(prompt)) =
        event.event
    else {
        panic!("expected PairingRequested local event");
    };
    assert!(remote
        .confirm_pin("desktop-ui-test", &prompt.pin_code)
        .await
        .expect("confirm_pin rpc"));

    let source_dir = tempfile::tempdir().expect("source dir");
    let source_path = source_dir.path().join("upload.bin");
    let payload: Vec<u8> = (0..300_000).map(|i| (i * 7 % 251) as u8).collect();
    std::fs::write(&source_path, &payload).expect("write source file");

    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(64);
    let returned_id = remote
        .upload_file(
            &source_path,
            ui_identity(),
            progress_tx,
            new_transfer_id(),
            Arc::new(Notify::new()),
        )
        .await
        .expect("upload_file");

    let mut saw_completed = false;
    let mut last_bytes = 0;
    while let Some(progress) = progress_rx.recv().await {
        assert_eq!(progress.direction, "outgoing");
        assert!(
            progress.bytes_transferred >= last_bytes,
            "progress must be monotonic"
        );
        last_bytes = progress.bytes_transferred;
        if progress.completed {
            saw_completed = true;
        }
    }
    assert!(saw_completed, "final progress event must be completed");
    assert_eq!(last_bytes, payload.len() as i64);
    assert!(!returned_id.is_empty());

    let received_path = config.data_dir.join("received").join("upload.bin");
    let received = std::fs::read(&received_path).expect("received file exists");
    assert_eq!(received, payload, "received file must be byte-identical");
}

/// Cancelling an outgoing transfer aborts it: `send_file` still returns
/// Ok, a `canceled` progress event is emitted, and nothing is finalized
/// on the daemon's disk.
#[tokio::test]
async fn cancel_aborts_transfer_and_finalizes_nothing() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let source_dir = tempfile::tempdir().expect("source dir");
    let source_path = source_dir.path().join("big.bin");
    std::fs::write(&source_path, vec![9u8; 4_000_000]).expect("write source");

    let remote = RemoteDeviceClient::connect("127.0.0.1", port)
        .await
        .expect("remote connect");

    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(256);
    let cancel = Arc::new(Notify::new());
    // Pre-arm the cancel: send_file's select! sees a stored permit and
    // takes the cancel branch on its first poll -- deterministic, no race
    // against the (fast, loopback) transfer.
    cancel.notify_one();

    remote
        .send_file(
            &source_path,
            ui_identity(),
            progress_tx,
            new_transfer_id(),
            cancel,
            0,
        )
        .await
        .expect("send_file returns Ok even when canceled");

    let mut saw_canceled = false;
    while let Some(progress) = progress_rx.recv().await {
        if progress.canceled {
            saw_canceled = true;
        }
    }
    assert!(saw_canceled, "a canceled progress event must be emitted");

    let received_path = config.data_dir.join("received").join("big.bin");
    assert!(
        std::fs::metadata(&received_path).is_err(),
        "a canceled transfer must not finalize a file on disk"
    );
}
