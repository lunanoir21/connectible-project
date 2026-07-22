//! Shared helpers for daemon integration tests under `tests/`: spawning
//! a real `connectibled` instance (real TLS 1.3 listener, real SQLite,
//! real mDNS advertise) on an ephemeral port, and dialing it with a
//! real TLS 1.3 gRPC client. Extracted here so every `tests/*.rs`
//! binary that needs a live daemon (`grpc_smoke.rs`, and
//! `fault_injection.rs` added for T-901) shares one implementation
//! instead of drifting copies of the same boilerplate.
//!
//! Not every helper here is used by every caller; `#[allow(dead_code)]`
//! on the module silences the per-binary "never used" warning that
//! would otherwise fire in whichever binary happens not to call a
//! given helper (each `tests/*.rs` file compiles this module into its
//! own separate binary).
#![allow(dead_code)]

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use connectibled::config::Config;
use connectibled::proto::connectible::v1::connectible_client::ConnectibleClient;
use connectibled::proto::connectible::v1::{
    local_event, ConfirmPinRequest, Identity, LocalEventsRequest, PairRequest,
};
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tonic::transport::{Certificate, Channel, ClientTlsConfig};

pub fn test_identity(device_id: &str, name: &str) -> Identity {
    Identity {
        device_id: device_id.to_string(),
        device_name: name.to_string(),
        platform: 0,
        device_type: 0,
        protocol_version: 1,
        app_version: "0.1.0".to_string(),
        capabilities: vec![],
    }
}

fn free_port() -> u16 {
    // Bind to port 0 to let the OS assign a free ephemeral port, then
    // drop the listener immediately so connectibled can bind it.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener.local_addr().expect("local addr").port()
}

/// T-909: serializes "pick an ephemeral port, then spawn a daemon and
/// confirm it (not some other, concurrently-starting test's daemon) is
/// the one actually listening on it" across every `spawn_test_daemon`
/// call in this test binary.
///
/// Root cause of the pre-existing flakiness this fixes: `free_port()`
/// finds a free port by binding then immediately dropping the
/// listener, and `connectibled::run()` binds that same port number
/// again, separately, some time later (after cert/DB/mDNS setup on its
/// own OS thread). That leaves a real window, between the drop and the
/// daemon's own bind, in which a *different* `spawn_test_daemon` call
/// racing on another test thread can grab the same just-freed port
/// number first. When that happened:
/// - The test whose daemon lost the race never got its listener bound
///   at all (the bind error is silently swallowed by `let _ =
///   connectibled::run(...).await` below), so any connection attempt
///   against its intended port surfaced as `ConnectionRefused`.
/// - The test whose daemon won the race was fine on its own, but the
///   *other* test's client -- still holding the port number it was
///   assigned before the collision -- would go on to dial that
///   winning daemon instead of its own. The TCP connect succeeds (it
///   is a real, live TLS listener), but the client trusts a CA
///   certificate read from its own tempdir, which is not the
///   certificate the daemon on the other end is presenting, so the
///   handshake fails downstream as `InvalidCertificate(BadSignature)`
///   rather than a clean connection error.
///
/// Holding this lock from the port pick through a confirmed TCP-level
/// connect closes the window completely: no other call can pick a
/// port while one is still being confirmed, so by the time the connect
/// below succeeds, it is provably this call's own daemon on the other
/// end, not a same-port collision with someone else's.
static PORT_ALLOC: Mutex<()> = Mutex::const_new(());

pub async fn spawn_test_daemon() -> (tempfile::TempDir, Config, u16) {
    let tmp = tempfile::tempdir().expect("tempdir");
    let data_dir = tmp.path().to_path_buf();

    let guard = PORT_ALLOC.lock().await;
    let port = free_port();

    let config = Config {
        data_dir: data_dir.clone(),
        tls_dir: data_dir.join("tls"),
        transfers_dir: data_dir.join("transfers"),
        db_path: data_dir.join("connectibled.db"),
        grpc_port: port,
        device_name: unique_device_name(),
    };
    std::fs::create_dir_all(&config.tls_dir).expect("create tls dir");
    std::fs::create_dir_all(&config.transfers_dir).expect("create transfers dir");
    // Pin received files to the temp data_dir so tests stay hermetic:
    // production now defaults to the OS Downloads folder, and a test must
    // never write payloads into the real ~/Downloads. This keeps the
    // historical data_dir/received location the transfer assertions
    // expect.
    connectibled::config::write_download_dir(&data_dir, &data_dir.join("received"))
        .expect("pin test download dir");

    // The daemon runs on its own dedicated OS thread with its own tokio
    // runtime, rather than as a task on the test's runtime. This mirrors
    // how the daemon actually runs in production (its own process) and
    // avoids the test's client connection sharing a runtime/scheduler
    // with the very server it is talking to.
    let run_config = config.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().expect("build daemon runtime");
        rt.block_on(async move {
            let _ = connectibled::run(run_config).await;
        });
    });

    // Poll with a real TCP connect instead of a fixed sleep-and-hope
    // delay: bounded, so a genuinely broken startup fails the test
    // loudly instead of hanging, and only as slow as the daemon
    // actually needs to be under whatever load the machine is under.
    wait_for_port_bound(port).await;
    drop(guard);

    (tmp, config, port)
}

async fn wait_for_port_bound(port: u16) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        if TcpStream::connect(("127.0.0.1", port)).await.is_ok() {
            return;
        }
        if tokio::time::Instant::now() >= deadline {
            panic!("daemon never bound to port {port} within 10s");
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// Distinct device names per spawned daemon (cosmetic only -- helps
/// tell instances apart in logs when several are running concurrently
/// within one test binary).
fn unique_device_name() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("Smoke-Test-Daemon-{n}")
}

/// Runs the full pair + PIN-confirm handshake over real TLS so a device
/// is persisted as paired, mirroring what a phone/desktop does before it
/// can appear in `list_devices` -- or, since SyncStream now requires the
/// sender to already be paired, before it can push any frame past
/// Identity at all.
pub async fn pair_device(config: &Config, port: u16, device_id: &str, name: &str) {
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

pub async fn connect_client(config: &Config, port: u16) -> ConnectibleClient<Channel> {
    let cert_pem = std::fs::read_to_string(config.tls_dir.join("cert.pem"))
        .expect("daemon must have generated a self-signed cert on first run");

    // Test client trusts exactly the one self-signed cert the daemon
    // just generated -- the same narrowly-scoped trust pattern real
    // desktop/mobile clients use (RULES.md T-033/T-044), not a blanket
    // "accept any certificate" verifier.
    let tls = ClientTlsConfig::new()
        .ca_certificate(Certificate::from_pem(cert_pem))
        .domain_name("localhost");

    let channel = Channel::from_shared(format!("https://127.0.0.1:{port}"))
        .expect("valid endpoint uri")
        .tls_config(tls)
        .expect("valid tls config")
        .connect()
        .await
        .expect("connect to daemon over TLS 1.3");

    ConnectibleClient::new(channel)
}
