//! End-to-end smoke test (T-052-style): boots a real `connectibled`
//! instance (real TLS 1.3 listener, real SQLite, real mDNS advertise)
//! and drives `Ping` and `ListDevices` over an actual network socket
//! using the generated gRPC client, verifying the TLS 1.3 wiring from
//! src/tls.rs works end-to-end and not just against a raw `openssl
//! s_client` handshake.

mod common;

use std::time::Duration;

use common::{connect_client, pair_device, spawn_test_daemon, test_identity};
use connectibled::proto::connectible::v1::sync_frame::Payload;
use connectibled::proto::connectible::v1::{
    local_event, ClipboardData, ConfirmPinRequest, GetLocalStateRequest, Identity,
    ListDevicesRequest, LocalEventsRequest, PairRequest, PingRequest, SyncFrame,
};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

#[tokio::test]
async fn ping_round_trips_over_real_tls13_connection() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    let mut client = connect_client(&config, port).await;

    let sent_at_ms = 123_456;
    let response = client
        .ping(PingRequest { sent_at_ms })
        .await
        .expect("ping rpc")
        .into_inner();

    assert_eq!(response.sent_at_ms, sent_at_ms);
    assert!(response.replied_at_ms > 0);
}

#[tokio::test]
async fn list_devices_is_empty_for_a_fresh_daemon() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    let mut client = connect_client(&config, port).await;

    let response = client
        .list_devices(ListDevicesRequest { online_only: false })
        .await
        .expect("list_devices rpc")
        .into_inner();

    assert!(response.devices.is_empty());
}

/// Drives a `ClipboardData` frame through a real `SyncStream` (real
/// TLS 1.3 socket -> tonic -> ConnectibleService::handle_frame ->
/// ClipboardSync -> X11ClipboardBackend) and asserts it lands on this
/// machine's actual clipboard, proving the wiring added in T-020..T-022
/// works end-to-end and not just at the unit level with a fake backend.
#[tokio::test]
async fn sync_stream_clipboard_frame_updates_real_clipboard() {
    let Some(local_backend) = connectibled::clipboard::detect_backend() else {
        eprintln!("skipping: no clipboard backend available in this environment");
        return;
    };

    let (_tmp, config, port) = spawn_test_daemon().await;
    // SyncStream frames other than Identity now require the sender to
    // already be paired (a fresh connection must not be able to write
    // the clipboard just by completing a TLS handshake) -- pair first,
    // matching what a real client does before ever opening SyncStream.
    pair_device(&config, port, "test-sender", "Test Sender").await;
    let mut client = connect_client(&config, port).await;

    let unique_marker = format!("connectible-e2e-{}", std::process::id());
    let content_hash = {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(unique_marker.as_bytes());
        hex::encode(hasher.finalize())
    };

    let marker_for_stream = unique_marker.clone();
    let outbound = async_stream::stream! {
        yield SyncFrame { payload: Some(Payload::Identity(Identity {
            device_id: "test-sender".to_string(),
            device_name: "Test Sender".to_string(),
            platform: 0,
            device_type: 0,
            protocol_version: 1,
            app_version: "0.1.0".to_string(),
            capabilities: vec![],
        })) };
        yield SyncFrame { payload: Some(Payload::Clipboard(ClipboardData {
            mime_type: "text/plain".to_string(),
            content: marker_for_stream.into_bytes(),
            captured_at_ms: 0,
            content_hash,
        })) };
    };

    let mut inbound = client
        .sync_stream(outbound)
        .await
        .expect("sync_stream rpc")
        .into_inner();
    // Wait for the Identity echo, confirming the server processed at
    // least that frame before we check the clipboard side effect of
    // the frame that followed it on the same stream.
    let _ = inbound.message().await;

    // Give the server a moment to process the ClipboardData frame that
    // was sent right after Identity on the same stream, then poll for
    // the expected content rather than a single fixed-delay read: the
    // Wayland backend's propagation is a compositor round-trip (write
    // -> Selection event -> offer.receive() -> Send event -> pipe
    // read), not the effectively-synchronous update X11 gives, so a
    // single delay is inherently racy against that backend.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    let clipboard_content = loop {
        let current = local_backend.get_text().expect("read local clipboard");
        if current.as_deref() == Some(unique_marker.as_str())
            || tokio::time::Instant::now() >= deadline
        {
            break current;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    };
    assert_eq!(clipboard_content.as_deref(), Some(unique_marker.as_str()));
}

/// The negative case the test above previously did *not* cover: a
/// connection that sends Identity but was never paired must not be
/// able to write the clipboard just by completing a TLS handshake.
/// Regression test for the SyncStream authorization gap fixed in
/// `handle_frame` (every non-Identity frame now requires
/// `devices.is_paired`).
#[tokio::test]
async fn sync_stream_clipboard_frame_from_an_unpaired_sender_is_rejected() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    let mut client = connect_client(&config, port).await;

    let marker = format!("connectible-unpaired-{}", std::process::id());
    let content_hash = {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(marker.as_bytes());
        hex::encode(hasher.finalize())
    };

    let marker_for_stream = marker.clone();
    let outbound = async_stream::stream! {
        yield SyncFrame { payload: Some(Payload::Identity(Identity {
            device_id: "never-paired-sender".to_string(),
            device_name: "Never Paired".to_string(),
            platform: 0,
            device_type: 0,
            protocol_version: 1,
            app_version: "0.1.0".to_string(),
            capabilities: vec![],
        })) };
        yield SyncFrame { payload: Some(Payload::Clipboard(ClipboardData {
            mime_type: "text/plain".to_string(),
            content: marker_for_stream.into_bytes(),
            captured_at_ms: 0,
            content_hash,
        })) };
    };

    let mut inbound = client
        .sync_stream(outbound)
        .await
        .expect("sync_stream rpc")
        .into_inner();

    // First message back is the Identity echo (always allowed).
    let identity_echo = inbound
        .message()
        .await
        .expect("stream healthy")
        .expect("identity echo");
    assert!(matches!(identity_echo.payload, Some(Payload::Identity(_))));

    // Second message must be an Unauthenticated error, not silence --
    // the clipboard frame was rejected, not just ignored.
    let rejection = inbound
        .message()
        .await
        .expect("stream healthy")
        .expect("rejection frame");
    match rejection.payload {
        Some(Payload::Error(err)) => {
            assert_eq!(
                err.code,
                connectibled::proto::connectible::v1::ErrorCode::Unauthenticated as i32
            );
        }
        other => panic!("expected an Unauthenticated Error frame, got {other:?}"),
    }
}

/// The full desktop-UI pairing story over a real TLS 1.3 loopback
/// connection: subscribe to local events (allowed, because the test
/// client genuinely connects from 127.0.0.1), trigger a PairRequest as
/// a "remote" device would, read the PIN off the local event stream
/// exactly like the desktop PIN dialog will, and confirm it.
#[tokio::test]
async fn local_event_stream_delivers_pin_that_pairs_over_real_tls() {
    let (_tmp, config, port) = spawn_test_daemon().await;

    let mut ui_client = connect_client(&config, port).await;
    let mut requester_client = connect_client(&config, port).await;

    let mut events = ui_client
        .subscribe_local_events(LocalEventsRequest {})
        .await
        .expect("loopback subscribe must be allowed")
        .into_inner();

    let state = ui_client
        .get_local_state(GetLocalStateRequest {})
        .await
        .expect("loopback get_local_state must be allowed")
        .into_inner();
    assert!(state.local_identity.is_some());
    assert!(state.capabilities.contains(&"file_transfer".to_string()));

    requester_client
        .pair(PairRequest {
            requester: Some(Identity {
                device_id: "e2e-requester".to_string(),
                device_name: "E2E Requester".to_string(),
                platform: 0,
                device_type: 0,
                protocol_version: 1,
                app_version: "0.1.0".to_string(),
                capabilities: vec![],
            }),
        })
        .await
        .expect("pair rpc");

    let event = tokio::time::timeout(Duration::from_secs(3), events.message())
        .await
        .expect("pairing event within 3s")
        .expect("stream healthy")
        .expect("stream not ended");

    let Some(local_event::Event::PairingRequested(prompt)) = event.event else {
        panic!("expected PairingRequested as the first local event");
    };
    assert_eq!(prompt.requester_device_id, "e2e-requester");

    let confirm = requester_client
        .confirm_pin(ConfirmPinRequest {
            device_id: "e2e-requester".to_string(),
            pin_code: prompt.pin_code,
        })
        .await
        .expect("confirm_pin rpc")
        .into_inner();
    assert!(
        confirm.verified,
        "PIN read from the UI event stream must pair the device"
    );

    let devices = requester_client
        .list_devices(ListDevicesRequest { online_only: false })
        .await
        .expect("list_devices rpc")
        .into_inner();
    assert!(devices.devices.iter().any(|d| d
        .identity
        .as_ref()
        .is_some_and(|i| i.device_id == "e2e-requester")));
}

/// PHASE 1 -- the exact "desktop can't see the phone" scenario, over a
/// real TLS 1.3 socket: a paired device that has an open SyncStream (it
/// sent its Identity) must be reported `online` by `list_devices` even
/// though mDNS never discovered it. This is the connection-based online
/// status the desktop relies on to show a live phone.
#[tokio::test]
async fn connected_peer_is_reported_online_over_real_tls() {
    let (_tmp, config, port) = spawn_test_daemon().await;
    pair_device(&config, port, "e2e-phone", "E2E Phone").await;

    // A fresh, un-connected paired device is offline.
    let mut observer = connect_client(&config, port).await;
    let before = observer
        .list_devices(ListDevicesRequest { online_only: false })
        .await
        .expect("list_devices rpc")
        .into_inner();
    assert!(
        before
            .devices
            .iter()
            .find(|d| d
                .identity
                .as_ref()
                .is_some_and(|i| i.device_id == "e2e-phone"))
            .is_some_and(|d| !d.online),
        "paired-but-not-connected device should be offline"
    );

    // Open a SyncStream and identify as that phone, holding it open.
    let mut phone = connect_client(&config, port).await;
    let (tx, rx) = mpsc::channel::<SyncFrame>(4);
    tx.send(SyncFrame {
        payload: Some(Payload::Identity(test_identity("e2e-phone", "E2E Phone"))),
    })
    .await
    .expect("send identity");
    let mut inbound = phone
        .sync_stream(ReceiverStream::new(rx))
        .await
        .expect("sync_stream rpc")
        .into_inner();
    let _ = inbound.message().await; // identity echo -> binding is registered

    // Now the same phone must show up as online.
    let after = observer
        .list_devices(ListDevicesRequest { online_only: true })
        .await
        .expect("list_devices rpc")
        .into_inner();
    assert!(
        after.devices.iter().any(|d| d
            .identity
            .as_ref()
            .is_some_and(|i| i.device_id == "e2e-phone")
            && d.online),
        "a connected paired device must be reported online without mDNS"
    );

    drop(tx); // close the stream
}

