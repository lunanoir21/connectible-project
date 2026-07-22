pub mod clipboard;
pub mod config;
pub mod db;
pub mod diagnostics;
pub mod discovery;
pub mod error;
pub mod grpc;
pub mod identity;
pub mod input;
pub mod pairing;
pub mod proto;
pub mod ratelimit;
pub mod status;
pub mod tls;
pub mod transfer;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use mdns_sd::ServiceDaemon;
use tokio_stream::wrappers::ReceiverStream;
use tonic::transport::Server;
use tracing::{info, warn};

use crate::clipboard::ClipboardSync;
use crate::grpc::ConnectibleService;
use crate::input::InputDispatcher;
use crate::proto::connectible::v1::connectible_server::ConnectibleServer;
use crate::proto::connectible::v1::sync_frame::Payload;
use crate::proto::connectible::v1::SyncFrame;
use crate::status::StatusHub;
use crate::transfer::TransferManager;

/// How often the clipboard is polled for local changes to broadcast to
/// paired peers (T-022). A short interval keeps propagation latency
/// low without busy-looping.
const CLIPBOARD_POLL_INTERVAL: Duration = Duration::from_millis(750);
/// How often queued remote-input events are drained and applied
/// (T-030); short enough that coalesced mouse movement still feels
/// responsive.
const INPUT_DRAIN_INTERVAL: Duration = Duration::from_millis(15);

/// Wires together config, storage, TLS, mDNS, and the gRPC service, then
/// serves forever on `config.grpc_port`. Extracted from `main.rs` into
/// the library crate so integration tests (see tests/) can spin up a
/// real daemon instance in-process rather than only unit-testing
/// individual modules.
pub async fn run(config: config::Config) -> anyhow::Result<()> {
    let device_id = identity::load_or_create_device_id(&config)?;
    info!(device_id = %device_id, device_name = %config.device_name, "loaded local identity");

    let pool = db::init_pool(&config).await?;
    let devices = db::DeviceRepository::new(pool);

    let tls_config = tls::load_or_create_server_config(&config)?;

    // Capability probes (T-021, T-030): absence of a working backend
    // disables the feature and is reflected in the advertised
    // capability list rather than crashing the daemon.
    let clipboard_backend = clipboard::detect_backend();
    let clipboard = clipboard_backend.map(|backend| Arc::new(ClipboardSync::new(backend)));
    let input_backend = input::detect_backend();
    let input = input_backend.map(|backend| Arc::new(InputDispatcher::new(backend)));

    let capabilities = identity::capability_list(clipboard.is_some(), input.is_some());

    let mdns = ServiceDaemon::new()?;
    let local_identity = identity::build_local_identity(&config, &device_id, capabilities);
    let hostname = config.device_name.replace(' ', "-");
    discovery::advertise(&mdns, &hostname, config.grpc_port, &local_identity)?;
    // `ServiceDaemon` is a cheap `Clone` handle onto a background thread
    // that is *not* tied to any particular handle's lifetime -- dropping
    // this local `mdns` binding would not stop it. `spawn_browser` gets
    // its own clone; `run` keeps the original alive so it can call
    // `.shutdown()` explicitly once serving stops (see below).
    let discovery_table = discovery::spawn_browser(mdns.clone(), device_id.clone())?;

    let peers = grpc::PeerRegistry::default();
    let transfers = Arc::new(TransferManager::new(config.transfers_dir.clone()));
    let uploads = Arc::new(transfer::upload::UploadRegistry::new(
        config.transfers_dir.clone(),
    ));
    let status = Arc::new(StatusHub::default());
    // T-310's tray/local-UI "clipboard sync" toggle: gates both the
    // outgoing poll loop below and incoming Clipboard frame application
    // in grpc::handle_frame. Lives here (not inside ClipboardSync
    // itself) so it is shared between the two independently of the
    // clipboard backend/module.
    let clipboard_sync_enabled = Arc::new(AtomicBool::new(true));

    let service = ConnectibleService {
        config: config.clone(),
        local_device_id: device_id,
        devices,
        pairing: Arc::new(pairing::PairingManager::default()),
        discovery: discovery_table,
        peers: peers.clone(),
        clipboard: clipboard.clone(),
        clipboard_sync_enabled: clipboard_sync_enabled.clone(),
        input,
        status,
        transfers,
        uploads,
        prepare_limiter: Arc::new(crate::ratelimit::RateLimiter::new(
            crate::grpc::PREPARE_PER_PEER,
            crate::grpc::PREPARE_WINDOW,
            crate::grpc::PREPARE_MAX_PEERS,
        )),
        started_at: std::time::Instant::now(),
    };

    if let Some(clipboard) = clipboard {
        spawn_clipboard_poll_loop(clipboard, peers, clipboard_sync_enabled);
    }
    if let Some(input) = &service.input {
        spawn_input_drain_loop(input.clone());
    }

    let addr = format!("0.0.0.0:{}", config.grpc_port).parse()?;
    info!(%addr, "gRPC server listening (TLS 1.3 only)");

    let incoming = tls::accept_loop(addr, tls_config).await?;
    let incoming = ReceiverStream::new(incoming);

    Server::builder()
        .add_service(ConnectibleServer::new(service))
        .serve_with_incoming_shutdown(incoming, shutdown_signal())
        .await?;

    // T-502: `discovery::spawn_browser`'s task blocks forever on
    // `receiver.recv()` reading mDNS events, because `ServiceDaemon`'s
    // background thread (and the channel `browse()` returned) stays
    // alive independent of any handle being dropped -- only an
    // explicit `.shutdown()` closes it. Without this, that
    // `spawn_blocking` task never completes, and Tokio's
    // `Runtime::drop()` (run at the end of `#[tokio::main]`, after this
    // function returns) blocks the process indefinitely waiting for
    // it, so SIGTERM would log "starting graceful shutdown" and then
    // the process would simply never exit. Bounded by a short timeout
    // so a slow/stuck mdns-sd shutdown can't itself hang exit forever.
    if let Ok(shutdown_rx) = mdns.shutdown() {
        let _ = tokio::time::timeout(Duration::from_secs(2), shutdown_rx.recv_async()).await;
    }

    Ok(())
}

/// Resolves on the first `SIGINT` (e.g. Ctrl-C) or `SIGTERM` received by
/// this process (T-111), so `run` can pass it to tonic's
/// `serve_with_incoming_shutdown` and let in-flight streams finish
/// instead of being killed mid-response.
async fn shutdown_signal() {
    let ctrl_c = async {
        // A failure to install the Ctrl-C handler is not fatal to
        // shutdown handling -- SIGTERM below still works -- so this
        // branch simply never resolves rather than erroring out.
        if let Err(e) = tokio::signal::ctrl_c().await {
            warn!(error = %e, "failed to listen for ctrl-c");
            std::future::pending::<()>().await;
        }
    };

    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut sigterm) => {
                sigterm.recv().await;
            }
            Err(e) => {
                warn!(error = %e, "failed to install sigterm handler");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => info!("received SIGINT, starting graceful shutdown"),
        _ = terminate => info!("received SIGTERM, starting graceful shutdown"),
    }
}

/// Background task (T-022): periodically checks the local clipboard
/// for changes and, when one is found, broadcasts it to every
/// currently-connected peer over their `SyncStream`. Skips polling
/// entirely while `sync_enabled` is false (T-310's clipboard sync
/// toggle), so a disabled sync does not even observe local changes,
/// let alone broadcast them.
fn spawn_clipboard_poll_loop(
    clipboard: Arc<ClipboardSync>,
    peers: grpc::PeerRegistry,
    sync_enabled: Arc<AtomicBool>,
) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(CLIPBOARD_POLL_INTERVAL);
        loop {
            interval.tick().await;
            if !sync_enabled.load(Ordering::Relaxed) {
                continue;
            }
            match clipboard.poll_local_change() {
                Ok(Some(data)) => {
                    peers
                        .broadcast(SyncFrame {
                            payload: Some(Payload::Clipboard(data)),
                        })
                        .await;
                }
                Ok(None) => {}
                Err(e) => warn!(error = %e, "clipboard poll failed"),
            }
        }
    });
}

/// Background task (T-030): drains and applies queued remote-input
/// events at a fixed cadence, so a burst of mouse-move frames received
/// faster than this interval gets coalesced (see InputDispatcher).
fn spawn_input_drain_loop(dispatcher: Arc<InputDispatcher>) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(INPUT_DRAIN_INTERVAL);
        loop {
            interval.tick().await;
            if let Err(e) = dispatcher.drain_and_apply() {
                warn!(error = %e, "failed to apply queued remote input event");
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    /// T-111: the graceful-shutdown future must resolve once this
    /// process receives SIGTERM, instead of the process dying to the
    /// signal's default disposition. Installing the `tokio::signal::
    /// unix::signal` listener (inside `shutdown_signal`) overrides that
    /// default disposition, so raising SIGTERM against our own pid here
    /// is safe -- it is caught by the listener rather than terminating
    /// the test process.
    #[tokio::test]
    async fn shutdown_signal_resolves_on_sigterm() {
        let handle = tokio::spawn(shutdown_signal());

        // Give the spawned task a chance to install the signal handler
        // before we raise the signal.
        tokio::time::sleep(Duration::from_millis(50)).await;

        let pid = std::process::id();
        let status = std::process::Command::new("kill")
            .args(["-TERM", &pid.to_string()])
            .status()
            .expect("failed to invoke kill(1)");
        assert!(status.success(), "kill -TERM did not succeed");

        tokio::time::timeout(Duration::from_secs(2), handle)
            .await
            .expect("shutdown_signal did not resolve within 2s of SIGTERM")
            .expect("shutdown_signal task panicked");
    }
}
