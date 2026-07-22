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
use tokio::sync::Notify;

fn free_port() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener.local_addr().expect("local addr").port()
}

/// A fresh data dir standing in for *this test's own* device identity
/// (Phase G, T-G3/T-G8): `RemoteDeviceClient` presents whatever
/// cert/key it finds under `<dir>/tls/` as its outbound TLS client
/// identity, generating one on first use exactly like a real daemon
/// does for its server identity -- this is deliberately a *different*
/// directory from the test daemon's own `config.data_dir` above, since
/// the client and the daemon it connects to are two distinct devices.
fn own_identity_dir() -> tempfile::TempDir {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::fs::create_dir_all(tmp.path().join("tls")).expect("create tls dir");
    tmp
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

    let own_dir = own_identity_dir();
    let remote = RemoteDeviceClient::connect(own_dir.path(), "127.0.0.1", port)
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
    let own_dir = own_identity_dir();
    let remote = RemoteDeviceClient::connect(own_dir.path(), "127.0.0.1", port)
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

    // Pair first (Phase I: T-I3 ported this off the legacy send_file,
    // which was cancel-fast enough to race ahead of the pairing gate
    // undetected -- upload_file's PrepareUpload step enforces pairing
    // synchronously before the cancelable feeder loop even starts, so
    // this is required here, unlike in the version this replaces).
    let own_dir = own_identity_dir();
    let ui = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("local client");
    let mut events = ui.subscribe_local_events().await.expect("subscribe");
    let remote = RemoteDeviceClient::connect(own_dir.path(), "127.0.0.1", port)
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

    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(256);
    let cancel = Arc::new(Notify::new());
    // Pre-arm the cancel: upload_file's feeder loop checks a flag set by
    // consuming this notify permit before its first read, so this is
    // deterministic rather than racing the (fast, loopback) transfer.
    cancel.notify_one();

    remote
        .upload_file(
            &source_path,
            ui_identity(),
            progress_tx,
            new_transfer_id(),
            cancel,
        )
        .await
        .expect("upload_file returns Ok even when canceled");

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

/// Phase G, T-G8: the mTLS identity gate end to end. A device that
/// paired as "desktop-ui-test" has its client-cert fingerprint pinned
/// (T-G4). A second, completely different identity -- its own distinct
/// self-signed cert, never involved in that pairing -- then tries to
/// call `prepare_upload` *claiming* to be "desktop-ui-test" in the
/// request body (the `sender` field is caller-supplied and independent
/// of the TLS connection's actual certificate). Before Phase G this
/// would have been accepted on `is_paired` alone; T-G5's fingerprint
/// check must reject it.
#[tokio::test]
async fn upload_file_rejects_a_sender_claiming_another_devices_pinned_identity() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    // The real "desktop-ui-test" pairs normally, pinning its own
    // identity dir's cert fingerprint against that device_id.
    let victim_dir = own_identity_dir();
    let ui = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("local client");
    let mut events = ui.subscribe_local_events().await.expect("subscribe");
    let victim = RemoteDeviceClient::connect(victim_dir.path(), "127.0.0.1", port)
        .await
        .expect("victim connect");
    victim.pair(ui_identity()).await.expect("pair rpc");
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
    assert!(victim
        .confirm_pin("desktop-ui-test", &prompt.pin_code)
        .await
        .expect("confirm_pin rpc"));

    // A distinct identity -- different cert/key, never paired as
    // anything -- connects fresh and claims the *victim's* device_id.
    let attacker_dir = own_identity_dir();
    let attacker = RemoteDeviceClient::connect(attacker_dir.path(), "127.0.0.1", port)
        .await
        .expect("attacker connect");

    let source_dir = tempfile::tempdir().expect("source dir");
    let source_path = source_dir.path().join("spoof.bin");
    std::fs::write(&source_path, b"this should never land").expect("write source file");

    let (progress_tx, _progress_rx) = tokio::sync::mpsc::channel(4);
    let result = attacker
        .upload_file(
            &source_path,
            ui_identity(), // claims device_id "desktop-ui-test", not attacker's own
            progress_tx,
            new_transfer_id(),
            Arc::new(Notify::new()),
        )
        .await;

    match result {
        Err(connectible_desktop_core::DesktopError::Rpc(status)) => {
            assert_eq!(
                status.code(),
                tonic::Code::PermissionDenied,
                "expected the fingerprint-mismatch rejection, got: {status}"
            );
        }
        other => panic!("expected a PermissionDenied rpc error, got: {other:?}"),
    }

    let received_path = config.data_dir.join("received").join("spoof.bin");
    assert!(
        std::fs::metadata(&received_path).is_err(),
        "a spoofed sender must never get a file onto disk"
    );
}

/// Phase J / T-J6: the persisted-transfer-history round trip through
/// `LocalDaemonClient` -- exactly what the desktop app does after
/// driving an outgoing send itself (`record_transfer_history` on
/// completion, then `list_transfer_history` to render the history
/// panel). Daemon-side semantics (loopback gating, incoming rows,
/// ordering) are covered in `daemon/tests/upload_transfer.rs`; this
/// proves the desktop client half.
#[tokio::test]
async fn transfer_history_round_trips_through_the_local_daemon_client() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let ui = LocalDaemonClient::connect(config.data_dir.clone(), port)
        .await
        .expect("local client");

    let transfer_id = new_transfer_id();
    ui.record_transfer_history(
        &transfer_id,
        "peer-mobile",
        "holiday.jpg",
        1_234_567,
        "outgoing",
        "completed",
        1_000,
        2_000,
    )
    .await
    .expect("record_transfer_history rpc");

    let entries = ui
        .list_transfer_history(10)
        .await
        .expect("list_transfer_history rpc");
    assert_eq!(
        entries.len(),
        1,
        "fresh daemon holds exactly the entry just recorded"
    );
    let entry = &entries[0];
    assert_eq!(entry.transfer_id, transfer_id);
    assert_eq!(entry.peer_device_id, "peer-mobile");
    assert_eq!(entry.file_name, "holiday.jpg");
    assert_eq!(entry.total_bytes, 1_234_567);
    assert_eq!(entry.direction, "outgoing");
    assert_eq!(entry.status, "completed");
    assert_eq!(entry.started_at_ms, 1_000);
    assert_eq!(entry.finished_at_ms, 2_000);
}
