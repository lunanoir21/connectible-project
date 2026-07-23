use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use tokio::sync::mpsc::Sender;
use tokio_stream::wrappers::ReceiverStream;
use tokio_stream::{Stream, StreamExt};
use tonic::{Request, Response, Status, Streaming};
use tracing::{debug, info, warn};

use crate::clipboard::ClipboardSync;
use crate::db::DeviceRepository;
use crate::identity;
use crate::input::InputDispatcher;
use crate::pairing::{self, PairingManager};
use crate::ratelimit::RateLimiter;
use crate::proto::connectible::v1::connectible_server::Connectible;
use crate::proto::connectible::v1::sync_frame::Payload;
use crate::proto::connectible::v1::{
    local_event, ClipboardHistoryEntry as ProtoClipboardHistoryEntry, ConfirmPinRequest,
    ConfirmPinResponse, DeviceInfo, DeviceType, DisconnectDeviceRequest, DisconnectDeviceResponse,
    DismissNotificationRequest, DismissNotificationResponse,
    Error as ProtoError, ErrorCode, ForgetDeviceRequest, ForgetDeviceResponse,
    DiagnosticCheck, GetLocalStateRequest, GetLocalStateResponse, GetPinnedFingerprintRequest,
    GetPinnedFingerprintResponse, ListDevicesRequest, ListDevicesResponse,
    NotificationData,
    RecordFingerprintRequest, RecordFingerprintResponse, RunDiagnosticsRequest,
    RunDiagnosticsResponse,
    LocalEvent, LocalEventsRequest, NearbyDevice, PairRequest, PairResponse,
    PairingCompletedLocalEvent, PairingRequestedLocalEvent, PingRequest, Platform, PongRequest,
    PreArmPairingCodeRequest,
    PreArmPairingCodeResponse, PrepareUploadRequest,
    PrepareUploadResponse, SetClipboardSyncEnabledRequest, SetClipboardSyncEnabledResponse,
    SetRemoteInputEnabledRequest, SetRemoteInputEnabledResponse, SyncFrame, TransferHistoryEntry,
    RecordTransferHistoryRequest, RecordTransferHistoryResponse, ListTransferHistoryRequest,
    ListTransferHistoryResponse, UploadFileOffer,
    UploadFilePart, UploadFileResult,
};
use crate::status::{StatusEvent, StatusHub};
use crate::transfer::upload::UploadRegistry;
use crate::transfer::TransferManager;
use crate::{config::Config, discovery::DiscoveryTable, error::DaemonError};

/// Registry of currently-open `SyncStream` connections' outbound
/// senders, so a locally-originated event (e.g. a clipboard change
/// detected on this machine) can be broadcast to every connected peer
/// rather than only echoed back on the connection that triggered it.
#[derive(Clone, Default)]
pub struct PeerRegistry {
    next_id: Arc<AtomicU64>,
    senders: Arc<Mutex<HashMap<u64, Sender<SyncFrame>>>>,
    /// Maps an open connection's id to the `device_id` it identified as
    /// (learned from the first `Identity` frame on its `SyncStream`).
    /// Lets `ListDevices` report a paired device as online whenever it
    /// holds a live connection -- the proto contract defines online as
    /// "mDNS-visible OR an open connection", not mDNS-visibility alone.
    devices: Arc<Mutex<HashMap<u64, String>>>,
}

impl PeerRegistry {
    fn register(&self, tx: Sender<SyncFrame>) -> u64 {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        self.senders
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(id, tx);
        id
    }

    /// Associates an already-registered connection with the `device_id`
    /// it announced, so `connected_device_ids` can surface it as online.
    /// Idempotent: re-sent `Identity` frames simply overwrite the entry.
    fn bind_device(&self, id: u64, device_id: String) {
        self.devices
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(id, device_id);
    }

    fn unregister(&self, id: u64) {
        self.senders
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&id);
        self.devices
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&id);
    }

    /// The set of `device_id`s that currently hold at least one live
    /// `SyncStream` connection to this daemon.
    pub fn connected_device_ids(&self) -> HashSet<String> {
        self.devices
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect()
    }

    /// Drops the live-connection attribution for `device_id` (T-102's
    /// "Disconnect" action from the local UI): removes every connection
    /// currently bound to it, so `connected_device_ids` -- and therefore
    /// `ListDevices`' online computation -- no longer counts it as
    /// connected. Returns whether any connection was actually found.
    ///
    /// This deliberately does not attempt to abort the peer's
    /// still-open `SyncStream` transport; that requires a per-connection
    /// cancellation handle this MVP registry does not carry, and the
    /// online/offline contract this exists to serve only cares about
    /// the attribution, not the raw socket. If the peer sends another
    /// frame (or reconnects), it re-binds and is counted online again.
    pub fn disconnect_device(&self, device_id: &str) -> bool {
        let ids: Vec<u64> = self
            .devices
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .iter()
            .filter(|(_, bound_id)| bound_id.as_str() == device_id)
            .map(|(conn_id, _)| *conn_id)
            .collect();
        for id in &ids {
            self.unregister(*id);
        }
        !ids.is_empty()
    }

    /// Sends `frame` to every currently-connected peer, dropping any
    /// sender whose receiving end has gone away.
    pub async fn broadcast(&self, frame: SyncFrame) {
        let senders: Vec<_> = self
            .senders
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect();
        for sender in senders {
            let _ = sender.send(frame.clone()).await;
        }
    }
}

/// Implements the `Connectible` gRPC service (T-006, T-009, T-010..T-031).
/// Holds shared, cloneable handles to the daemon's persistent and
/// in-memory state; the struct itself is cheap to clone since every
/// field is already an `Arc`-backed handle.
#[derive(Clone)]
pub struct ConnectibleService {
    pub config: Config,
    pub local_device_id: String,
    pub devices: DeviceRepository,
    /// Persisted transfer history (Phase J). Incoming rows are written
    /// directly by `upload_file`; outgoing rows arrive via the
    /// loopback-only `RecordTransferHistory` RPC, since an outgoing
    /// send is driven by the UI process talking straight to a remote
    /// peer's daemon and this daemon never otherwise observes it.
    pub transfer_history: crate::db::TransferHistoryRepository,
    pub pairing: Arc<PairingManager>,
    pub discovery: DiscoveryTable,
    pub peers: PeerRegistry,
    pub clipboard: Option<Arc<ClipboardSync>>,
    /// T-310's clipboard-sync toggle gate, shared with the poll loop
    /// spawned in lib.rs. Lives outside `ClipboardSync` itself so both
    /// the outgoing poll loop and the incoming `handle_frame` dispatch
    /// below can check the same flag. `None` (no clipboard backend at
    /// all) is distinct from "disabled" -- `set_clipboard_sync_enabled`
    /// rejects the call in that case rather than pretending to toggle
    /// something that does not exist.
    pub clipboard_sync_enabled: Arc<AtomicBool>,
    pub input: Option<Arc<InputDispatcher>>,
    pub status: Arc<StatusHub>,
    pub transfers: Arc<TransferManager>,
    /// Dedicated file-upload session/token store (PrepareUpload ->
    /// UploadFile, TASKS.md Phase A), separate from `transfers`' chunk
    /// path. Holds a ticket per accepted offer between the two RPCs.
    pub uploads: Arc<UploadRegistry>,
    /// T-C7: per-peer `PrepareUpload` throttle. A paired peer that floods
    /// prepare requests (each mints tokens + touches disk state) is bounded
    /// to [`PREPARE_PER_PEER`] per [`PREPARE_WINDOW`]; excess returns
    /// `RESOURCE_EXHAUSTED`. Generous vs. real use (one prepare per send
    /// session, however many files) so only an abusive burst is throttled.
    pub prepare_limiter: Arc<RateLimiter<String>>,
    /// When this daemon process started, for the System Doctor uptime
    /// check (T-F7).
    pub started_at: std::time::Instant,
}

/// T-C7 policy: prepare calls per peer per window, and the max distinct
/// peers tracked (memory bound against a spoofed-device-id flood).
pub const PREPARE_PER_PEER: u32 = 60;
pub const PREPARE_WINDOW: std::time::Duration = std::time::Duration::from_secs(60);
pub const PREPARE_MAX_PEERS: usize = 1024;

/// T-security: max files a single `PrepareUpload` call may list. Bounds
/// how many permanent registry tickets one request can mint --
/// `PREPARE_PER_PEER`/`PREPARE_WINDOW` only bound call *frequency*, not
/// the size of an individual call. Generous vs. any real "send a folder"
/// use case.
pub const MAX_FILES_PER_PREPARE: usize = 500;

/// Outcome of [`ConnectibleService::verify_peer_identity`] (Phase G,
/// T-G5). Kept as a distinct type from `bool` so every call site is
/// forced to choose the right rejection reason/error code rather than
/// collapsing both failure modes into one generic "not paired".
enum PeerIdentityCheck {
    Ok,
    NotPaired,
    FingerprintMismatch,
}

type SyncStreamOut = Pin<Box<dyn Stream<Item = Result<SyncFrame, Status>> + Send + 'static>>;
type LocalEventsOut = Pin<Box<dyn Stream<Item = Result<LocalEvent, Status>> + Send + 'static>>;

impl ConnectibleService {
    /// Downloaded/received files are finalized here, kept separate from
    /// `config.transfers_dir` which holds only in-progress `.part` files
    /// (see ARCHITECTURE.md section 4). Resolved fresh each call so the
    /// desktop Settings folder picker (`set_download_dir`) takes effect
    /// live; defaults to the OS Downloads folder rather than a buried
    /// data-dir path so received files land where the user can find them.
    fn downloads_dir(&self) -> std::path::PathBuf {
        crate::config::resolve_download_dir(&self.config.data_dir)
    }

    /// The combined pairing + identity check every paired-only RPC or
    /// SyncStream frame must pass (Phase G, T-G5): `device_id` must (a)
    /// actually be paired, and (b) if a client-cert fingerprint is
    /// pinned for it (T-G4), the connection's presented fingerprint
    /// must match. A pinned device presenting a different -- or no --
    /// fingerprint is `FingerprintMismatch`, distinct from `NotPaired`,
    /// since the device *is* paired; this specific connection just
    /// isn't provably it (spoofed device_id, or a genuine re-key that
    /// needs re-pairing). A paired device with nothing pinned yet
    /// (pre-Phase-G, or paired before its first fingerprint-bearing
    /// reconnect) passes on the paired check alone -- the one-time
    /// backfill grace window every other TOFU path in this codebase
    /// already gives a never-pinned device.
    async fn verify_peer_identity(
        &self,
        device_id: &str,
        client_fingerprint: Option<&str>,
    ) -> PeerIdentityCheck {
        if device_id.is_empty() || !matches!(self.devices.is_paired(device_id).await, Ok(true)) {
            return PeerIdentityCheck::NotPaired;
        }
        if let Ok(Some(pinned)) = self.devices.fingerprint(device_id).await {
            if client_fingerprint != Some(pinned.as_str()) {
                return PeerIdentityCheck::FingerprintMismatch;
            }
        }
        PeerIdentityCheck::Ok
    }

    /// Persists one terminal `upload_file` outcome (Phase J, T-J2a) as
    /// an `incoming` `transfer_history` row. Best-effort: a DB write
    /// failure here must not fail the RPC the file itself already
    /// completed (or failed) on its own terms -- it only means this one
    /// history entry is missing, logged rather than propagated.
    async fn record_incoming_transfer_history(
        &self,
        ticket: &crate::transfer::upload::UploadTicket,
        status: &str,
        started_at_ms: i64,
    ) {
        let entry = crate::db::NewTransferHistoryEntry {
            transfer_id: ticket.file_id.clone(),
            peer_device_id: ticket.device_id.clone(),
            file_name: ticket.file_name.clone(),
            total_bytes: ticket.total_bytes,
            direction: "incoming".to_string(),
            status: status.to_string(),
            started_at_ms,
            finished_at_ms: pairing::now_ms(),
        };
        if let Err(e) = self.transfer_history.record(&entry).await {
            warn!(error = %e, file_id = %ticket.file_id, "failed to persist incoming transfer history");
        }
    }

    /// Persists both UI toggle states (T-X12) to the daemon's data dir so
    /// a user's clipboard-sync / remote-input choices survive a restart.
    /// Writes the current state of BOTH toggles (whichever handler called
    /// this only changed one), so the file is always self-consistent.
    /// Best-effort: a write failure leaves the in-memory state correct
    /// for this run and is only logged, never surfaced to the caller.
    fn persist_ui_toggles(&self) {
        let toggles = crate::config::UiToggles {
            clipboard_sync_enabled: self.clipboard_sync_enabled.load(Ordering::Relaxed),
            remote_input_enabled: self.input.as_ref().is_none_or(|d| d.is_enabled()),
        };
        if let Err(e) = crate::config::write_ui_toggles(&self.config.data_dir, toggles) {
            warn!(error = %e, "failed to persist UI toggle states");
        }
    }

    /// Dispatches one `SyncFrame` payload received on an open
    /// `SyncStream` connection (T-009 routing, extended in T-020..T-031
    /// to cover every oneof case). `peer_device_id` is updated in place
    /// whenever an `Identity` frame arrives, so later frames on the same
    /// stream can be attributed to their sender (e.g. clipboard history
    /// source, notification forwarding). Returns `false` if the
    /// outbound channel has closed and the caller should stop reading.
    async fn handle_frame(
        &self,
        payload: Payload,
        tx: &Sender<SyncFrame>,
        peer_device_id: &mut String,
        conn_id: u64,
        client_fingerprint: Option<&str>,
    ) -> bool {
        // Every frame except Identity requires the sender to already be a
        // paired device whose connection identity checks out (Phase G,
        // T-G5). Identity itself is exempt (it's what lets a fresh
        // connection attribute itself in the first place); by the time a
        // legitimate peer opens SyncStream at all, ConfirmPin has already
        // run (see PairingModel::_activate / RemoteDeviceClient on both
        // clients), so a genuinely paired peer is never blocked here.
        // Fail closed: an empty peer_device_id (no Identity frame yet), a
        // paired-state lookup error, or a client-cert fingerprint that
        // does not match what was pinned at pairing time are all treated
        // as not-authorized -- without this, any device that merely
        // completes a TLS handshake (or that knows a paired peer's
        // device_id and claims it) could push clipboard writes or input
        // events into an unrelated machine it was never paired with.
        if !matches!(payload, Payload::Identity(_)) {
            match self
                .verify_peer_identity(peer_device_id, client_fingerprint)
                .await
            {
                PeerIdentityCheck::Ok => {}
                PeerIdentityCheck::NotPaired => {
                    warn!(device_id = %peer_device_id, "rejecting SyncStream frame from an unpaired/unidentified peer");
                    return send_error(
                        tx,
                        ErrorCode::Unauthenticated,
                        "this connection is not paired".to_string(),
                    )
                    .await;
                }
                PeerIdentityCheck::FingerprintMismatch => {
                    warn!(device_id = %peer_device_id, "rejecting SyncStream frame: client certificate does not match the pinned fingerprint");
                    return send_error(
                        tx,
                        ErrorCode::FingerprintChanged,
                        "this device's identity does not match what was pinned during pairing"
                            .to_string(),
                    )
                    .await;
                }
            }
        }

        match payload {
            Payload::Identity(identity) => {
                *peer_device_id = identity.device_id.clone();
                // Attribute this connection to its device so the peer is
                // reported online for as long as the stream is open.
                self.peers.bind_device(conn_id, identity.device_id.clone());
                // If the peer is already paired, persist the real Identity
                // it just sent (platform/device_type/name) and refresh
                // last_seen -- upsert_paired preserves paired_at_ms. This
                // replaces the placeholder metadata written at ConfirmPin
                // time, when the full Identity was not yet available. For a
                // not-yet-paired requester (Identity arriving mid-pairing)
                // we intentionally do nothing: ConfirmPin persists it.
                match self.devices.is_paired(&identity.device_id).await {
                    Ok(true) => {
                        if let Err(e) = self
                            .devices
                            .upsert_paired(&identity, pairing::now_ms())
                            .await
                        {
                            warn!(error = %e, device_id = %identity.device_id, "failed to persist connected peer identity");
                        }
                    }
                    Ok(false) => {}
                    Err(e) => {
                        warn!(error = %e, device_id = %identity.device_id, "failed to check paired state for connected peer");
                    }
                }
                let echoed = SyncFrame {
                    payload: Some(Payload::Identity(identity)),
                };
                tx.send(echoed).await.is_ok()
            }

            Payload::Clipboard(data) => {
                if !self.clipboard_sync_enabled.load(Ordering::Relaxed) {
                    debug!("clipboard frame ignored: clipboard sync is disabled locally");
                } else if let Some(clipboard) = &self.clipboard {
                    if let Err(e) = clipboard.apply_incoming(&data, peer_device_id) {
                        warn!(error = %e, "failed to apply incoming clipboard update");
                    }
                } else {
                    debug!("clipboard frame received but no clipboard backend is available");
                }
                true
            }

            Payload::InputEvent(event) => {
                if let Some(dispatcher) = &self.input {
                    dispatcher.enqueue(&event);
                } else {
                    debug!("remote input event received but no input backend is available");
                }
                true
            }

            Payload::BatteryStatus(status) => {
                self.status.update_battery(status);
                true
            }

            Payload::Notification(notification) => {
                self.status.apply_notification(notification);
                true
            }

            Payload::Error(err) => {
                warn!(code = err.code, message = %err.message, "peer reported an error");
                true
            }
        }
    }
}

async fn send_error(tx: &Sender<SyncFrame>, code: ErrorCode, message: String) -> bool {
    let frame = SyncFrame {
        payload: Some(Payload::Error(ProtoError {
            code: code as i32,
            message,
            details: Default::default(),
        })),
    };
    tx.send(frame).await.is_ok()
}

/// Gate for the local-UI RPCs (SubscribeLocalEvents / GetLocalState):
/// only connections whose transport peer address is loopback may call
/// them, because the event stream carries pairing PINs in plaintext
/// (see the "Local UI messages" section of connectible.proto). A
/// missing peer address (`None`) is treated as untrusted and denied --
/// fail closed, never open.
fn require_loopback<T>(request: &Request<T>) -> Result<(), Status> {
    match request.remote_addr() {
        Some(addr) if addr.ip().is_loopback() => Ok(()),
        _ => Err(Status::permission_denied(
            "this RPC is restricted to local (loopback) callers",
        )),
    }
}

/// Bridges one broadcast source into the per-subscriber mpsc feeding a
/// SubscribeLocalEvents response stream. Ends when either the source
/// closes or the subscriber disconnects; a lagged subscriber skips the
/// dropped events rather than terminating the stream.
fn forward_events<T, F>(
    mut source: tokio::sync::broadcast::Receiver<T>,
    tx: Sender<LocalEvent>,
    map: F,
) where
    T: Clone + Send + 'static,
    F: Fn(T) -> local_event::Event + Send + 'static,
{
    tokio::spawn(async move {
        loop {
            match source.recv().await {
                Ok(item) => {
                    let event = LocalEvent {
                        event: Some(map(item)),
                    };
                    if tx.send(event).await.is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                    debug!(skipped, "local event subscriber lagged; skipping");
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    });
}

fn to_proto_history_entry(
    entry: crate::clipboard::ClipboardHistoryEntry,
) -> ProtoClipboardHistoryEntry {
    ProtoClipboardHistoryEntry {
        content: entry.content,
        mime_type: entry.mime_type,
        captured_at_ms: entry.captured_at_ms,
        source: entry.source,
        oversized: entry.oversized,
        byte_size: entry.byte_size,
    }
}

#[tonic::async_trait]
impl Connectible for ConnectibleService {
    type SyncStreamStream = SyncStreamOut;

    async fn sync_stream(
        &self,
        request: Request<Streaming<SyncFrame>>,
    ) -> Result<Response<Self::SyncStreamStream>, Status> {
        // Captured once, up front, from this connection's TLS session --
        // every frame on this stream shares the same fingerprint for the
        // stream's lifetime (Phase G, T-G5).
        let client_fingerprint = crate::grpc::peer_client_cert_fingerprint(&request);
        let mut inbound = request.into_inner();
        let (tx, rx) = tokio::sync::mpsc::channel(64);
        let peer_id = self.peers.register(tx.clone());

        let service = self.clone();
        tokio::spawn(async move {
            let mut peer_device_id = String::from("unknown");

            while let Some(frame) = inbound.next().await {
                match frame {
                    Ok(frame) => {
                        let Some(payload) = frame.payload else {
                            continue;
                        };
                        if !service
                            .handle_frame(
                                payload,
                                &tx,
                                &mut peer_device_id,
                                peer_id,
                                client_fingerprint.as_deref(),
                            )
                            .await
                        {
                            break;
                        }
                    }
                    Err(status) => {
                        warn!(%status, "sync_stream inbound error");
                        break;
                    }
                }
            }

            service.peers.unregister(peer_id);
        });

        let out = ReceiverStream::new(rx).map(Ok);
        Ok(Response::new(Box::pin(out)))
    }

    async fn pair(&self, request: Request<PairRequest>) -> Result<Response<PairResponse>, Status> {
        let requester = request
            .into_inner()
            .requester
            .ok_or_else(|| Status::invalid_argument("missing requester identity"))?;

        // T-015: duplicate-pairing short-circuit -- an already-paired
        // device is accepted immediately with no PIN required.
        if self
            .devices
            .is_paired(&requester.device_id)
            .await
            .map_err(to_status)?
        {
            self.devices
                .update_last_seen(&requester.device_id, pairing::now_ms())
                .await
                .map_err(to_status)?;
            info!(device_id = %requester.device_id, "pair: already paired, short-circuiting");
            return Ok(Response::new(PairResponse {
                accepted: true,
                pin_expires_at_ms: 0,
                error: None,
            }));
        }

        match self
            .pairing
            .create_pending(&requester.device_id, &requester.device_name)
        {
            Ok(expires_at_ms) => {
                info!(device_id = %requester.device_id, "pair: PIN dialog requested locally");
                Ok(Response::new(PairResponse {
                    accepted: true,
                    pin_expires_at_ms: expires_at_ms,
                    error: None,
                }))
            }
            // T-403: a burst of Pair calls from the same peer is
            // throttled rather than repeatedly re-popping the local PIN
            // dialog; reported in the response body like ConfirmPin's
            // rejection path, not a gRPC-level Status, since this is a
            // normal/expected outcome the caller should display, not a
            // transport-level failure.
            Err(err) => {
                warn!(device_id = %requester.device_id, error = %err, "pair: rate limited");
                Ok(Response::new(PairResponse {
                    accepted: false,
                    pin_expires_at_ms: 0,
                    error: Some(ProtoError {
                        code: err.code() as i32,
                        message: err.to_string(),
                        details: Default::default(),
                    }),
                }))
            }
        }
    }

    async fn confirm_pin(
        &self,
        request: Request<ConfirmPinRequest>,
    ) -> Result<Response<ConfirmPinResponse>, Status> {
        // Captured before `into_inner()` consumes `request` -- this is the
        // fingerprint of whatever client certificate the *requester*
        // presented on the very connection carrying this confirmation
        // (Phase G, T-G4). Symmetric to the client-side TOFU pin: there,
        // the connecting device pins the *server's* cert on first use;
        // here, the responder pins the *client's* cert the first time
        // that client successfully proves it knows the PIN.
        let client_fingerprint = crate::grpc::peer_client_cert_fingerprint(&request);
        let req = request.into_inner();

        match self.pairing.confirm(&req.device_id, &req.pin_code) {
            Ok(()) => {
                // T-013: persist the device on successful pairing. We do
                // not have the requester's full Identity here (only what
                // ConfirmPinRequest carries), so the caller is expected to
                // have exchanged Identity over SyncStream already; the
                // minimal record uses what pairing has on file.
                let name = self
                    .pairing
                    .requester_name(&req.device_id)
                    .unwrap_or_else(|| "Unknown Device".to_string());
                let identity = crate::proto::connectible::v1::Identity {
                    device_id: req.device_id.clone(),
                    device_name: name,
                    platform: 0,
                    device_type: 0,
                    protocol_version: identity::PROTOCOL_VERSION,
                    app_version: identity::APP_VERSION.to_string(),
                    capabilities: vec![],
                };
                self.devices
                    .upsert_paired(&identity, pairing::now_ms())
                    .await
                    .map_err(to_status)?;

                if let Some(fingerprint) = client_fingerprint {
                    // Best-effort: a device presenting no client cert yet
                    // (old build, or T-G-phase mid-rollout) still pairs
                    // successfully -- it just has nothing pinned here,
                    // same as any pre-Phase-G paired device (T-G5's
                    // backfill grace covers it on a later reconnect).
                    if let Err(e) = self.devices.set_fingerprint(&req.device_id, &fingerprint).await
                    {
                        warn!(device_id = %req.device_id, error = %e, "failed to pin requester client-cert fingerprint");
                    }
                }

                Ok(Response::new(ConfirmPinResponse {
                    verified: true,
                    error: None,
                }))
            }
            Err(err) => Ok(Response::new(ConfirmPinResponse {
                verified: false,
                error: Some(ProtoError {
                    code: err.code() as i32,
                    message: err.to_string(),
                    details: Default::default(),
                }),
            })),
        }
    }

    async fn list_devices(
        &self,
        request: Request<ListDevicesRequest>,
    ) -> Result<Response<ListDevicesResponse>, Status> {
        let online_only = request.into_inner().online_only;
        let paired = self.devices.list().await.map_err(to_status)?;
        let discovered = self.discovery.list();
        let discovered_ids: HashSet<_> = discovered.iter().map(|d| d.device_id.clone()).collect();
        // A paired device is online if it is mDNS-visible OR currently
        // holds a live SyncStream connection. The latter is what makes a
        // connected phone (which has no local daemon advertising a fixed
        // service, and may not be mDNS-visible from here) show as online.
        let connected_ids = self.peers.connected_device_ids();

        let mut devices = Vec::with_capacity(paired.len());
        for record in paired {
            let online = discovered_ids.contains(&record.device_id)
                || connected_ids.contains(&record.device_id);
            if online_only && !online {
                continue;
            }
            // Surface the real platform/device_type persisted for the peer
            // (stored as their enum str-name in the devices table) rather
            // than a hardcoded PLATFORM_UNSPECIFIED, so the UI can show the
            // correct device icon.
            let platform =
                Platform::from_str_name(&record.platform).unwrap_or(Platform::Unspecified) as i32;
            let device_type = DeviceType::from_str_name(&record.device_type)
                .unwrap_or(DeviceType::Unspecified) as i32;
            devices.push(DeviceInfo {
                identity: Some(crate::proto::connectible::v1::Identity {
                    device_id: record.device_id,
                    device_name: record.device_name,
                    platform,
                    device_type,
                    protocol_version: identity::PROTOCOL_VERSION,
                    app_version: String::new(),
                    capabilities: vec![],
                }),
                online,
                paired_at_ms: record.paired_at_ms,
                last_seen_ms: record.last_seen_ms,
            });
        }

        Ok(Response::new(ListDevicesResponse { devices }))
    }

    /// Loopback-only (T-102): the local UI's "Disconnect" action for a
    /// paired device. See `PeerRegistry::disconnect_device` for exactly
    /// what "disconnect" means here (attribution drop, not a forced
    /// transport close).
    async fn disconnect_device(
        &self,
        request: Request<DisconnectDeviceRequest>,
    ) -> Result<Response<DisconnectDeviceResponse>, Status> {
        require_loopback(&request)?;
        let device_id = request.into_inner().device_id;
        let was_connected = self.peers.disconnect_device(&device_id);
        info!(device_id = %device_id, was_connected, "disconnect_device: local UI requested peer disconnect");
        Ok(Response::new(DisconnectDeviceResponse { was_connected }))
    }

    /// Loopback-only (T-K5): the local UI dismissed a mirrored
    /// notification. Applies the dismissal to this daemon's own status
    /// (so the local UI's own list reflects it immediately, exactly the
    /// same path an incoming dismissal from a peer already takes) and
    /// broadcasts it to every currently-connected peer, so the
    /// originating device can clear the real system notification too.
    async fn dismiss_notification(
        &self,
        request: Request<DismissNotificationRequest>,
    ) -> Result<Response<DismissNotificationResponse>, Status> {
        require_loopback(&request)?;
        let notification_id = request.into_inner().notification_id;
        let frame = NotificationData {
            notification_id: notification_id.clone(),
            is_dismissal: true,
            ..Default::default()
        };
        self.status.apply_notification(frame.clone());
        self.peers
            .broadcast(SyncFrame {
                payload: Some(Payload::Notification(frame)),
            })
            .await;
        info!(notification_id = %notification_id, "dismiss_notification: local UI dismissed a mirrored notification");
        Ok(Response::new(DismissNotificationResponse {}))
    }

    /// Loopback-only (T-307): the local UI's "Forget device" action --
    /// permanently removes the device's row so it no longer appears in
    /// `ListDevices` and a future reconnect must go through a fresh
    /// Pair/ConfirmPin PIN exchange (T-015's short-circuit no longer
    /// applies once the row is gone). Also drops any live-connection
    /// attribution so a forgotten device does not linger as "online".
    async fn forget_device(
        &self,
        request: Request<ForgetDeviceRequest>,
    ) -> Result<Response<ForgetDeviceResponse>, Status> {
        require_loopback(&request)?;
        let device_id = request.into_inner().device_id;
        let removed = self.devices.delete(&device_id).await.map_err(to_status)?;
        self.peers.disconnect_device(&device_id);
        info!(device_id = %device_id, removed, "forget_device: local UI requested permanent removal");
        Ok(Response::new(ForgetDeviceResponse { removed }))
    }

    async fn ping(&self, request: Request<PingRequest>) -> Result<Response<PongRequest>, Status> {
        let sent_at_ms = request.into_inner().sent_at_ms;
        Ok(Response::new(PongRequest {
            sent_at_ms,
            replied_at_ms: pairing::now_ms(),
        }))
    }

    // Dedicated file upload, step 1 (TASKS.md T-A5). Authorizes the
    // sender against the paired set (an unpaired peer is refused before
    // any bytes move -- same trust level as the rest of the app, keyed on
    // the claimed device_id; per-device cert binding is TOFU, Phase C),
    // then per file mints a token and reports how many bytes are already
    // on disk so the sender can resume. UploadFile (T-A6) does the bytes.
    async fn prepare_upload(
        &self,
        request: Request<PrepareUploadRequest>,
    ) -> Result<Response<PrepareUploadResponse>, Status> {
        // Captured before `into_inner()` (Phase G, T-G5).
        let client_fingerprint = crate::grpc::peer_client_cert_fingerprint(&request);
        let req = request.into_inner();
        let sender = req
            .sender
            .ok_or_else(|| Status::invalid_argument("missing sender identity"))?;

        // Only a paired device whose connection identity checks out may
        // push files here. Reject the whole session up front rather than
        // per file -- an unpaired (or spoofed-device_id) sender has no
        // business learning anything about our disk state.
        match self
            .verify_peer_identity(&sender.device_id, client_fingerprint.as_deref())
            .await
        {
            PeerIdentityCheck::Ok => {}
            PeerIdentityCheck::NotPaired => {
                warn!(device_id = %sender.device_id, "prepare_upload: rejecting unpaired sender");
                return Err(Status::unauthenticated("device is not paired"));
            }
            PeerIdentityCheck::FingerprintMismatch => {
                warn!(device_id = %sender.device_id, "prepare_upload: rejecting sender whose client certificate does not match the pinned fingerprint");
                return Err(Status::permission_denied(
                    "this device's identity does not match what was pinned during pairing",
                ));
            }
        }

        // T-C7: throttle prepare floods per peer (after the paired check, so
        // an unpaired flood is already handled above and this budget is
        // spent only on authenticated peers).
        if !self.prepare_limiter.check(sender.device_id.clone()) {
            warn!(device_id = %sender.device_id, "prepare_upload: rate limit exceeded");
            return Err(Status::resource_exhausted(
                "too many transfer requests; slow down",
            ));
        }

        // T-security: a paired-but-malicious (or just buggy) sender could
        // otherwise list tens of thousands of files in one call, minting
        // that many permanent registry tickets in a single request --
        // the per-peer prepare_limiter above only bounds call *frequency*,
        // not the size of one call. Reject the whole batch rather than
        // silently truncating it, so the sender's own file count and the
        // offers it gets back always agree.
        if req.files.len() > MAX_FILES_PER_PREPARE {
            warn!(
                device_id = %sender.device_id,
                files = req.files.len(),
                "prepare_upload: rejecting oversized batch"
            );
            return Err(Status::invalid_argument(format!(
                "at most {MAX_FILES_PER_PREPARE} files per PrepareUpload call"
            )));
        }

        // Group this transfer under a session id (caller-supplied, or one
        // we mint) so per-file tokens/progress share a key.
        let session_id = if req.session_id.is_empty() {
            uuid::Uuid::new_v4().to_string()
        } else {
            req.session_id.clone()
        };

        let offers = req
            .files
            .iter()
            .map(|meta| {
                // T-security: `UploadWriter::finish` only treats a short
                // stream as `Incomplete` when `total_bytes > 0` -- a
                // sender declaring `file_size_bytes <= 0` would skip
                // that guard entirely and finalize on whatever bytes
                // happened to arrive. Reject the claim up front instead
                // of relying on a downstream check that only applies to
                // the positive case.
                if meta.file_size_bytes <= 0 {
                    warn!(
                        device_id = %sender.device_id,
                        file_id = %meta.file_id,
                        file_size_bytes = meta.file_size_bytes,
                        "prepare_upload: rejecting a non-positive declared size"
                    );
                    return UploadFileOffer {
                        file_id: meta.file_id.clone(),
                        accepted: false,
                        resume_offset_bytes: 0,
                        token: String::new(),
                        reject_reason: ErrorCode::FileTransferFailed.as_str_name().to_string(),
                    };
                }
                match self.uploads.accept(&session_id, &sender.device_id, meta) {
                    Some((token, resume_offset_bytes)) => UploadFileOffer {
                        file_id: meta.file_id.clone(),
                        accepted: true,
                        resume_offset_bytes,
                        token,
                        reject_reason: String::new(),
                    },
                    None => {
                        warn!(
                            device_id = %sender.device_id,
                            file_id = %meta.file_id,
                            "prepare_upload: registry is full, declining this file"
                        );
                        UploadFileOffer {
                            file_id: meta.file_id.clone(),
                            accepted: false,
                            resume_offset_bytes: 0,
                            token: String::new(),
                            reject_reason: ErrorCode::Internal.as_str_name().to_string(),
                        }
                    }
                }
            })
            .collect();

        info!(
            device_id = %sender.device_id,
            session_id = %session_id,
            files = req.files.len(),
            "prepare_upload: accepted"
        );
        Ok(Response::new(PrepareUploadResponse { session_id, offers }))
    }

    // Dedicated file upload, step 2 (TASKS.md T-A6/A7/A8). The first
    // frame is the header (validated against a live PrepareUpload ticket);
    // every subsequent frame is a raw byte chunk written straight to the
    // partial on disk while a streaming SHA-256 is folded. At end-of-
    // stream the file is finalized into the download dir (hash verified),
    // reported as a resumable partial (stream dropped early), or discarded
    // (hash mismatch). Backpressure is the HTTP/2 stream's own flow
    // control -- the sender awaits each chunk.
    async fn upload_file(
        &self,
        request: Request<Streaming<UploadFilePart>>,
    ) -> Result<Response<UploadFileResult>, Status> {
        use crate::proto::connectible::v1::upload_file_part::Part;
        use crate::transfer::upload::{UploadOutcome, UploadWriter};

        let mut stream = request.into_inner();

        let first = stream
            .message()
            .await?
            .ok_or_else(|| Status::invalid_argument("empty upload stream"))?;
        let header = match first.part {
            Some(Part::Header(h)) => h,
            _ => {
                return Err(Status::invalid_argument(
                    "first UploadFile message must be a header",
                ))
            }
        };

        // The token ties this byte stream to a file the receiver actually
        // agreed to accept in PrepareUpload; reject anything else.
        let ticket = self
            .uploads
            .resolve(&header.session_id, &header.file_id, &header.token)
            .ok_or_else(|| Status::permission_denied("unknown or mismatched upload token"))?;
        let started_at_ms = pairing::now_ms();

        let mut writer = UploadWriter::open(
            &ticket,
            header.offset_bytes,
            self.transfers.progress_sender(),
        )
        .await
        .map_err(|e| Status::internal(format!("open upload sink: {e}")))?;

        while let Some(part) = stream.message().await? {
            match part.part {
                Some(Part::Chunk(data)) => {
                    writer
                        .write(&data)
                        .await
                        .map_err(|e| Status::internal(format!("write upload chunk: {e}")))?;
                }
                Some(Part::Header(_)) => {
                    return Err(Status::invalid_argument(
                        "unexpected second header in UploadFile stream",
                    ))
                }
                None => {} // empty frame -- ignore
            }
        }

        let dest_dir = self.downloads_dir();
        let outcome = writer
            .finish(&dest_dir)
            .await
            .map_err(|e| Status::internal(format!("finalize upload: {e}")))?;

        let result = match outcome {
            UploadOutcome::Completed { path, bytes } => {
                self.uploads.finish(&header.token);
                info!(
                    file_id = %header.file_id,
                    path = %path.display(),
                    bytes,
                    "upload_file: completed + verified"
                );
                self.record_incoming_transfer_history(&ticket, "completed", started_at_ms)
                    .await;
                UploadFileResult {
                    file_id: header.file_id,
                    completed: true,
                    bytes_received: bytes,
                    hash_ok: true,
                }
            }
            UploadOutcome::HashMismatch { bytes } => {
                self.uploads.finish(&header.token);
                warn!(file_id = %header.file_id, "upload_file: hash mismatch, discarded");
                self.record_incoming_transfer_history(&ticket, "failed", started_at_ms)
                    .await;
                UploadFileResult {
                    file_id: header.file_id,
                    completed: false,
                    bytes_received: bytes,
                    hash_ok: false,
                }
            }
            UploadOutcome::Incomplete { bytes } => {
                // Ticket + partial deliberately left in place so a retry
                // resumes; nothing to log as an error.
                UploadFileResult {
                    file_id: header.file_id,
                    completed: false,
                    bytes_received: bytes,
                    hash_ok: false,
                }
            }
        };
        Ok(Response::new(result))
    }

    type SubscribeLocalEventsStream = LocalEventsOut;

    async fn subscribe_local_events(
        &self,
        request: Request<LocalEventsRequest>,
    ) -> Result<Response<Self::SubscribeLocalEventsStream>, Status> {
        require_loopback(&request)?;

        let (tx, rx) = tokio::sync::mpsc::channel(64);

        forward_events(self.pairing.subscribe(), tx.clone(), |event| {
            local_event::Event::PairingRequested(PairingRequestedLocalEvent {
                requester_device_id: event.requester_device_id,
                requester_device_name: event.requester_device_name,
                pin_code: event.pin_code,
                pin_expires_at_ms: event.pin_expires_at_ms,
            })
        });

        forward_events(self.pairing.subscribe_completed(), tx.clone(), |event| {
            local_event::Event::PairingCompleted(PairingCompletedLocalEvent {
                requester_device_id: event.requester_device_id,
                requester_device_name: event.requester_device_name,
            })
        });

        forward_events(self.status.subscribe(), tx.clone(), |event| match event {
            StatusEvent::Battery(battery) => local_event::Event::Battery(battery),
            StatusEvent::Notification(notification) => {
                local_event::Event::Notification(notification)
            }
        });

        forward_events(
            self.transfers.subscribe(),
            tx.clone(),
            local_event::Event::TransferProgress,
        );

        if let Some(clipboard) = &self.clipboard {
            forward_events(clipboard.subscribe(), tx, |entry| {
                local_event::Event::Clipboard(to_proto_history_entry(entry))
            });
        }

        let out = ReceiverStream::new(rx).map(Ok);
        Ok(Response::new(Box::pin(out)))
    }

    async fn get_local_state(
        &self,
        request: Request<GetLocalStateRequest>,
    ) -> Result<Response<GetLocalStateResponse>, Status> {
        require_loopback(&request)?;

        let capabilities =
            identity::capability_list(self.clipboard.is_some(), self.input.is_some());
        let local_identity = identity::build_local_identity(
            &self.config,
            &self.local_device_id,
            capabilities.clone(),
        );

        let clipboard_history = self
            .clipboard
            .as_ref()
            .map(|clipboard| {
                clipboard
                    .history()
                    .into_iter()
                    .map(to_proto_history_entry)
                    .collect()
            })
            .unwrap_or_default();

        let nearby_devices = self
            .discovery
            .list()
            .into_iter()
            .map(|device| NearbyDevice {
                device_id: device.device_id,
                device_name: device.device_name,
                platform: device.platform,
                addr: device.addr.to_string(),
                port: device.port as u32,
                protocol_version: device.protocol_version.parse().unwrap_or(0),
            })
            .collect();

        Ok(Response::new(GetLocalStateResponse {
            local_identity: Some(local_identity),
            capabilities,
            clipboard_history,
            latest_battery: self.status.latest_battery(),
            notifications: self.status.list_notifications(),
            nearby_devices,
            remote_input_enabled: self
                .input
                .as_ref()
                .map(|dispatcher| dispatcher.is_enabled())
                .unwrap_or(false),
            clipboard_sync_enabled: self.clipboard.is_some()
                && self.clipboard_sync_enabled.load(Ordering::Relaxed),
        }))
    }

    /// Loopback-only (T-309): gates whether incoming `RemoteInputEvent`
    /// frames are applied to the input backend. Rejected with
    /// FAILED_PRECONDITION when no input backend is compiled/detected
    /// at all -- there is nothing to toggle in that case.
    async fn set_remote_input_enabled(
        &self,
        request: Request<SetRemoteInputEnabledRequest>,
    ) -> Result<Response<SetRemoteInputEnabledResponse>, Status> {
        require_loopback(&request)?;
        let enabled = request.into_inner().enabled;
        let Some(dispatcher) = &self.input else {
            return Err(Status::failed_precondition(
                "no input backend is available on this daemon",
            ));
        };
        dispatcher.set_enabled(enabled);
        // T-X12: persist so the choice survives a daemon restart.
        self.persist_ui_toggles();
        info!(
            enabled,
            "set_remote_input_enabled: local UI toggled remote input dispatch"
        );
        Ok(Response::new(SetRemoteInputEnabledResponse {
            enabled: dispatcher.is_enabled(),
        }))
    }

    /// Loopback-only (T-310): gates whether the daemon polls/broadcasts
    /// local clipboard changes and applies incoming ones. Rejected with
    /// FAILED_PRECONDITION when no clipboard backend is available at
    /// all -- there is nothing to toggle in that case.
    async fn set_clipboard_sync_enabled(
        &self,
        request: Request<SetClipboardSyncEnabledRequest>,
    ) -> Result<Response<SetClipboardSyncEnabledResponse>, Status> {
        require_loopback(&request)?;
        let enabled = request.into_inner().enabled;
        if self.clipboard.is_none() {
            return Err(Status::failed_precondition(
                "no clipboard backend is available on this daemon",
            ));
        }
        self.clipboard_sync_enabled
            .store(enabled, Ordering::Relaxed);
        // T-X12: persist so the choice survives a daemon restart.
        self.persist_ui_toggles();
        info!(
            enabled,
            "set_clipboard_sync_enabled: local UI toggled clipboard sync"
        );
        Ok(Response::new(SetClipboardSyncEnabledResponse {
            enabled: self.clipboard_sync_enabled.load(Ordering::Relaxed),
        }))
    }

    /// TOFU (T-C2/C3), loopback-only: the pinned cert fingerprint for a
    /// paired device. Empty string = no pin yet (unknown device, or a
    /// pre-TOFU device awaiting record-on-first-use). The local client
    /// calls this before dialing so its verifier can compare the presented
    /// cert against the pin.
    async fn get_pinned_fingerprint(
        &self,
        request: Request<GetPinnedFingerprintRequest>,
    ) -> Result<Response<GetPinnedFingerprintResponse>, Status> {
        require_loopback(&request)?;
        let device_id = request.into_inner().device_id;
        let fingerprint = self
            .devices
            .fingerprint(&device_id)
            .await
            .map_err(|e| Status::internal(format!("fingerprint lookup failed: {e}")))?
            .unwrap_or_default();
        Ok(Response::new(GetPinnedFingerprintResponse { fingerprint }))
    }

    /// TOFU (T-C2/C5), loopback-only: pins a device's observed cert
    /// fingerprint (record-on-first-use, and the backfill for pre-TOFU
    /// devices). No-op + `recorded=false` for an unknown device_id. Note it
    /// overwrites whatever was there: the caller only records on first use
    /// (pin was empty) or via an explicit re-pair, never to silently accept
    /// a *changed* key -- that path is blocked in the verifier.
    async fn record_fingerprint(
        &self,
        request: Request<RecordFingerprintRequest>,
    ) -> Result<Response<RecordFingerprintResponse>, Status> {
        require_loopback(&request)?;
        let req = request.into_inner();
        if req.fingerprint.is_empty() {
            return Err(Status::invalid_argument("empty fingerprint"));
        }
        let known = self
            .devices
            .is_paired(&req.device_id)
            .await
            .map_err(|e| Status::internal(format!("paired lookup failed: {e}")))?;
        if !known {
            return Ok(Response::new(RecordFingerprintResponse { recorded: false }));
        }
        self.devices
            .set_fingerprint(&req.device_id, &req.fingerprint)
            .await
            .map_err(|e| Status::internal(format!("fingerprint write failed: {e}")))?;
        info!(device_id = %req.device_id, "record_fingerprint: pinned peer cert");
        Ok(Response::new(RecordFingerprintResponse { recorded: true }))
    }

    /// System Doctor (T-F7), loopback-only: runs the shared diagnostics
    /// engine in-process (so port/DB/backend checks reflect this live
    /// daemon) and returns structured results. The `connectibled doctor`
    /// CLI runs the same registry, so the UI and terminal never drift.
    async fn run_diagnostics(
        &self,
        request: Request<RunDiagnosticsRequest>,
    ) -> Result<Response<RunDiagnosticsResponse>, Status> {
        require_loopback(&request)?;
        let check_id = request.into_inner().check_id;
        let registry = crate::diagnostics::default_registry();
        let ctx = crate::diagnostics::DiagnosticsContext {
            config: self.config.clone(),
            runtime: Some(crate::diagnostics::DaemonRuntime {
                started_at: self.started_at,
            }),
        };

        let (results, worst) = if check_id.is_empty() {
            let report = registry.run_all(&ctx).await;
            (report.results, report.worst)
        } else {
            match registry.run_one(&check_id, &ctx).await {
                Some(r) => {
                    let worst = r.status;
                    (vec![r], worst)
                }
                None => return Err(Status::not_found(format!("unknown check id: {check_id}"))),
            }
        };

        let checks = results.into_iter().map(diagnostic_to_proto).collect();
        Ok(Response::new(RunDiagnosticsResponse {
            checks,
            worst: worst.as_str().to_string(),
        }))
    }

    /// Loopback-only: pre-generates a PIN for the local UI to embed in a
    /// pairing QR code -- see `PairingManager::pre_arm`. The requester
    /// identity isn't known yet (no inbound connection has happened),
    /// so unlike `pair()` this never touches `self.devices` and never
    /// fires `PairingRequestedEvent`; that still happens normally, once,
    /// when someone actually calls `Pair` and consumes the code.
    async fn pre_arm_pairing_code(
        &self,
        request: Request<PreArmPairingCodeRequest>,
    ) -> Result<Response<PreArmPairingCodeResponse>, Status> {
        require_loopback(&request)?;
        let (pin_code, pin_expires_at_ms) = self.pairing.pre_arm();
        info!("pre_arm_pairing_code: local UI generated a pairing QR code");
        Ok(Response::new(PreArmPairingCodeResponse {
            pin_code,
            pin_expires_at_ms,
            error: None,
        }))
    }

    /// Loopback-only (Phase J, T-J2b): the local UI reports the outcome
    /// of an outgoing send it drove itself directly against a remote
    /// peer's daemon (`RemoteDeviceClient::upload_file`) -- this
    /// daemon otherwise never observes that transfer at all, unlike an
    /// incoming one (recorded directly by `upload_file` above).
    async fn record_transfer_history(
        &self,
        request: Request<RecordTransferHistoryRequest>,
    ) -> Result<Response<RecordTransferHistoryResponse>, Status> {
        require_loopback(&request)?;
        let entry = request
            .into_inner()
            .entry
            .ok_or_else(|| Status::invalid_argument("missing entry"))?;
        self.transfer_history
            .record(&crate::db::NewTransferHistoryEntry {
                transfer_id: entry.transfer_id,
                peer_device_id: entry.peer_device_id,
                file_name: entry.file_name,
                total_bytes: entry.total_bytes,
                direction: entry.direction,
                status: entry.status,
                started_at_ms: entry.started_at_ms,
                finished_at_ms: entry.finished_at_ms,
            })
            .await
            .map_err(|e| Status::internal(format!("transfer history write failed: {e}")))?;
        Ok(Response::new(RecordTransferHistoryResponse {}))
    }

    /// Loopback-only (Phase J, T-J2b): paginated read of persisted
    /// transfer history (both directions -- incoming rows written
    /// directly by `upload_file`, outgoing rows relayed in via
    /// `record_transfer_history` above).
    async fn list_transfer_history(
        &self,
        request: Request<ListTransferHistoryRequest>,
    ) -> Result<Response<ListTransferHistoryResponse>, Status> {
        require_loopback(&request)?;
        let limit = request.into_inner().limit;
        let records = self
            .transfer_history
            .list(limit as i64)
            .await
            .map_err(|e| Status::internal(format!("transfer history read failed: {e}")))?;
        let entries = records
            .into_iter()
            .map(|r| TransferHistoryEntry {
                transfer_id: r.transfer_id,
                peer_device_id: r.peer_device_id,
                file_name: r.file_name,
                total_bytes: r.total_bytes,
                direction: r.direction,
                status: r.status,
                started_at_ms: r.started_at_ms,
                finished_at_ms: r.finished_at_ms,
            })
            .collect();
        Ok(Response::new(ListTransferHistoryResponse { entries }))
    }
}

/// Converts an engine [`CheckResult`](crate::diagnostics::CheckResult) into
/// its wire form (empty strings for absent optional fields).
fn diagnostic_to_proto(r: crate::diagnostics::CheckResult) -> DiagnosticCheck {
    DiagnosticCheck {
        id: r.id,
        title: r.title,
        category: r.category.as_str().to_string(),
        status: r.status.as_str().to_string(),
        summary: r.summary,
        detail: r.detail.unwrap_or_default(),
        remediation: r.remediation.unwrap_or_default(),
        data: r.data.into_iter().collect(),
        summary_key: r.summary_key.unwrap_or_default().to_string(),
        remediation_key: r.remediation_key.unwrap_or_default().to_string(),
    }
}

/// Maps a `DaemonError` to a matchable `tonic::Status` code via its
/// `ErrorCode` (T-405), instead of collapsing every failure to
/// `Status::internal` -- callers of unary RPCs (e.g. a future
/// `ListDevices` failure) can then distinguish "not found" from
/// "rate limited" from "actually internal" the same way the in-stream
/// `Error` frame path already lets them (see `send_error` below).
fn to_status(err: DaemonError) -> Status {
    let code = match err.code() {
        ErrorCode::DeviceNotFound => tonic::Code::NotFound,
        ErrorCode::PairingRejected | ErrorCode::Unauthenticated => tonic::Code::PermissionDenied,
        ErrorCode::PairingTimeout => tonic::Code::DeadlineExceeded,
        ErrorCode::RateLimited => tonic::Code::ResourceExhausted,
        ErrorCode::UnsupportedPlatform | ErrorCode::ProtocolVersionMismatch => {
            tonic::Code::FailedPrecondition
        }
        ErrorCode::FileTransferFailed | ErrorCode::ChecksumMismatch => tonic::Code::Aborted,
        // TOFU: a client-side trust rejection (the daemon itself never
        // emits this, since it does not verify client certs), mapped for
        // match-exhaustiveness to a permission failure.
        ErrorCode::FingerprintChanged => tonic::Code::PermissionDenied,
        ErrorCode::Internal | ErrorCode::Unspecified => tonic::Code::Internal,
    };
    Status::new(code, err.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::DiscoveryTable;
    use crate::error::Result;
    use crate::input::InputBackend;
    use crate::proto::connectible::v1::{Identity, MouseButton, UploadFileMeta};
    use sqlx::sqlite::SqlitePoolOptions;
    use std::path::PathBuf;

    /// In-process fake input backend (RULES.md: no test may depend on
    /// real hardware/services) so T-309's toggle can be exercised with
    /// a wired `input` backend without a real X11/ydotoold session.
    struct NoopInputBackend;

    impl InputBackend for NoopInputBackend {
        fn mouse_move(&self, _x: f32, _y: f32) -> Result<()> {
            Ok(())
        }
        fn mouse_button(&self, _button: MouseButton, _pressed: bool) -> Result<()> {
            Ok(())
        }
        fn scroll(&self, _delta_x: f32, _delta_y: f32) -> Result<()> {
            Ok(())
        }
        fn key(&self, _key_code: u32, _pressed: bool) -> Result<()> {
            Ok(())
        }
    }

    /// In-process fake clipboard backend, same rationale as
    /// `NoopInputBackend` above but for T-310's toggle -- always
    /// reports empty/no-op rather than touching a real X11 selection.
    struct NoopClipboardBackend;

    impl crate::clipboard::ClipboardBackend for NoopClipboardBackend {
        fn get_content(&self) -> Result<Option<crate::clipboard::ClipboardContent>> {
            Ok(None)
        }
        fn set_content(&self, _content: &crate::clipboard::ClipboardContent) -> Result<()> {
            Ok(())
        }
    }

    async fn test_service() -> ConnectibleService {
        test_service_with(PathBuf::from("/tmp"), None, true).await
    }

    /// Parameterized fixture (T-X12): lets a test pin the `data_dir` (so
    /// the persisted `ui_toggles` file lands somewhere isolated), wire a
    /// clipboard backend (so the clipboard-sync toggle RPC is accepted),
    /// and choose the starting clipboard-sync state (as lib.rs does from
    /// `load_ui_toggles`). `test_service()` keeps the old defaults.
    async fn test_service_with(
        data_dir: PathBuf,
        clipboard: Option<Arc<ClipboardSync>>,
        clipboard_sync_enabled: bool,
    ) -> ConnectibleService {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("in-memory sqlite connect");
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .expect("run migrations");

        ConnectibleService {
            config: Config {
                data_dir,
                tls_dir: PathBuf::from("/tmp"),
                transfers_dir: PathBuf::from("/tmp"),
                db_path: PathBuf::from(":memory:"),
                grpc_port: 0,
                device_name: "Test Responder".to_string(),
            },
            local_device_id: "responder-id".to_string(),
            devices: DeviceRepository::new(pool.clone(), [9u8; 32]),
            transfer_history: crate::db::TransferHistoryRepository::new(pool),
            pairing: std::sync::Arc::new(PairingManager::default()),
            discovery: DiscoveryTable::default(),
            peers: PeerRegistry::default(),
            clipboard,
            clipboard_sync_enabled: Arc::new(AtomicBool::new(clipboard_sync_enabled)),
            input: None,
            status: Arc::new(StatusHub::default()),
            transfers: Arc::new(TransferManager::new()),
            uploads: Arc::new(UploadRegistry::new(PathBuf::from("/tmp"))),
            prepare_limiter: Arc::new(RateLimiter::new(
                PREPARE_PER_PEER,
                PREPARE_WINDOW,
                PREPARE_MAX_PEERS,
            )),
            started_at: std::time::Instant::now(),
        }
    }

    fn requester_identity() -> Identity {
        Identity {
            device_id: "requester-id".to_string(),
            device_name: "Anil's Phone".to_string(),
            platform: 0,
            device_type: 0,
            protocol_version: 1,
            app_version: "0.1.0".to_string(),
            capabilities: vec![],
        }
    }

    /// T-016: drives a full Pair -> ConfirmPin -> ListDevices flow
    /// through the actual RPC handler implementations (not just the
    /// underlying PairingManager unit tested in pairing::tests),
    /// asserting the requester ends up persisted and visible.
    #[tokio::test]
    async fn full_pairing_flow_persists_and_lists_the_device() {
        let service = test_service().await;

        let pair_response = service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc")
            .into_inner();
        assert!(pair_response.accepted);
        assert!(pair_response.pin_expires_at_ms > 0);

        let pin = service
            .pairing
            .peek_pin("requester-id")
            .expect("pin was generated for the requester");

        let confirm_response = service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc")
            .into_inner();
        assert!(confirm_response.verified, "correct pin must verify");

        let list_response = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert_eq!(list_response.devices.len(), 1);
        assert_eq!(
            list_response.devices[0]
                .identity
                .as_ref()
                .unwrap()
                .device_id,
            "requester-id"
        );
        assert!(list_response.devices[0].paired_at_ms > 0);
    }

    /// T-A5: PrepareUpload refuses an unpaired sender outright, and for a
    /// paired one returns an accepted offer carrying a token that resolves
    /// back in the upload registry (so UploadFile can validate the stream).
    #[tokio::test]
    async fn prepare_upload_rejects_unpaired_and_accepts_paired() {
        let service = test_service().await;
        let sender = requester_identity();
        // Unique file_id so a leftover /tmp/*.part from a prior run can't
        // make the resume offset flaky (test_service pins transfers_dir to
        // /tmp).
        let file_id = format!("t-a5-{}", uuid::Uuid::new_v4());
        let file = UploadFileMeta {
            file_id: file_id.clone(),
            file_name: "photo.png".to_string(),
            file_size_bytes: 2048,
            file_hash: "abc123".to_string(),
            mime_type: "image/png".to_string(),
        };

        // Unpaired -> UNAUTHENTICATED, before any offer is minted.
        let err = service
            .prepare_upload(Request::new(PrepareUploadRequest {
                sender: Some(sender.clone()),
                session_id: "sess-1".to_string(),
                files: vec![file.clone()],
            }))
            .await
            .expect_err("unpaired sender must be rejected");
        assert_eq!(err.code(), tonic::Code::Unauthenticated);

        // Pair the device, then the same request is accepted.
        service
            .devices
            .upsert_paired(&sender, crate::pairing::now_ms())
            .await
            .expect("pair the sender");

        let resp = service
            .prepare_upload(Request::new(PrepareUploadRequest {
                sender: Some(sender.clone()),
                session_id: "sess-1".to_string(),
                files: vec![file.clone()],
            }))
            .await
            .expect("paired sender accepted")
            .into_inner();

        assert_eq!(resp.session_id, "sess-1");
        assert_eq!(resp.offers.len(), 1);
        let offer = &resp.offers[0];
        assert!(offer.accepted);
        assert_eq!(offer.file_id, file_id);
        assert!(!offer.token.is_empty(), "an accepted offer carries a token");
        assert_eq!(offer.resume_offset_bytes, 0, "no partial on disk yet");

        // The token the sender got back resolves to a live ticket.
        let ticket = service
            .uploads
            .resolve("sess-1", &file_id, &offer.token)
            .expect("minted token resolves in the registry");
        assert_eq!(ticket.total_bytes, 2048);
        assert_eq!(ticket.expected_hash, "abc123");
    }

    /// T-C7: a paired peer flooding PrepareUpload is throttled -- the first
    /// PREPARE_PER_PEER calls succeed, then further ones return
    /// RESOURCE_EXHAUSTED rather than minting unbounded tokens/disk state.
    #[tokio::test]
    async fn prepare_upload_throttles_a_peer_flood() {
        let service = test_service().await;
        let sender = requester_identity();
        service
            .devices
            .upsert_paired(&sender, crate::pairing::now_ms())
            .await
            .expect("pair the sender");

        let mk = || {
            Request::new(PrepareUploadRequest {
                sender: Some(sender.clone()),
                session_id: format!("sess-{}", uuid::Uuid::new_v4()),
                files: vec![UploadFileMeta {
                    file_id: format!("f-{}", uuid::Uuid::new_v4()),
                    file_name: "x.bin".to_string(),
                    file_size_bytes: 1,
                    file_hash: "h".to_string(),
                    mime_type: String::new(),
                }],
            })
        };

        // Exactly PREPARE_PER_PEER succeed within the window.
        for i in 0..PREPARE_PER_PEER {
            service
                .prepare_upload(mk())
                .await
                .unwrap_or_else(|e| panic!("call {i} should be allowed: {e:?}"));
        }
        // The next one is throttled.
        let err = service
            .prepare_upload(mk())
            .await
            .expect_err("flood past the limit must be rejected");
        assert_eq!(err.code(), tonic::Code::ResourceExhausted);
    }

    /// PIN expiry / rejection path: a wrong PIN must not persist the
    /// device and must report `verified = false` with an error detail.
    #[tokio::test]
    async fn wrong_pin_does_not_pair_the_device() {
        let service = test_service().await;

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");

        let confirm_response = service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: "000000".to_string(),
            }))
            .await
            .expect("confirm_pin rpc")
            .into_inner();
        assert!(!confirm_response.verified);
        assert!(confirm_response.error.is_some());

        let list_response = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert!(list_response.devices.is_empty());
    }

    /// T-015: re-pairing an already-paired device short-circuits with
    /// no PIN required and does not reset `paired_at_ms`.
    #[tokio::test]
    async fn repeat_pairing_short_circuits_without_a_new_pin() {
        let service = test_service().await;

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("first pair rpc");
        let pin = service
            .pairing
            .peek_pin("requester-id")
            .expect("pin exists");
        service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc");

        let second_pair_response = service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("second pair rpc")
            .into_inner();

        assert!(second_pair_response.accepted);
        assert_eq!(
            second_pair_response.pin_expires_at_ms, 0,
            "already-paired device must not receive a fresh PIN"
        );
    }

    /// A paired device with a live SyncStream connection must be reported
    /// online even when it is NOT mDNS-visible from this daemon -- the
    /// core of "the desktop can now see the connected phone". Dropping the
    /// connection flips it back to offline.
    #[tokio::test]
    async fn connected_peer_is_online_without_mdns() {
        let service = test_service().await;

        // Pair + persist the requester (no mDNS discovery involved).
        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");
        let pin = service.pairing.peek_pin("requester-id").expect("pin");
        service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc");

        // Nothing in the discovery table, but the peer holds a live stream.
        assert!(service.discovery.list().is_empty());
        let (tx, _rx) = tokio::sync::mpsc::channel(4);
        let conn_id = service.peers.register(tx);
        service
            .peers
            .bind_device(conn_id, "requester-id".to_string());

        let online = service
            .list_devices(Request::new(ListDevicesRequest { online_only: true }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert_eq!(online.devices.len(), 1, "connected peer must appear");
        assert!(
            online.devices[0].online,
            "a peer with an open connection must be online without mDNS"
        );

        // Connection drops -> back to offline.
        service.peers.unregister(conn_id);
        let after = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert!(
            !after.devices[0].online,
            "peer must be offline once its connection is gone"
        );
    }

    /// The full Identity a paired peer sends over its SyncStream replaces
    /// the placeholder platform/type written at ConfirmPin time, and
    /// ListDevices surfaces the real values (fixes the "always
    /// PLATFORM_UNSPECIFIED" placeholder).
    #[tokio::test]
    async fn identity_frame_persists_real_platform_for_paired_peer() {
        let service = test_service().await;

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");
        let pin = service.pairing.peek_pin("requester-id").expect("pin");
        service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc");

        // Real identity arrives on the stream after activation.
        let real = Identity {
            device_id: "requester-id".to_string(),
            device_name: "Anil's Phone".to_string(),
            platform: Platform::Android as i32,
            device_type: DeviceType::Phone as i32,
            protocol_version: 1,
            app_version: "0.1.0".to_string(),
            capabilities: vec![],
        };
        let (tx, mut rx) = tokio::sync::mpsc::channel(4);
        let conn = service.peers.register(tx.clone());
        let mut peer = String::from("unknown");
        assert!(
            service
                .handle_frame(Payload::Identity(real), &tx, &mut peer, conn, None)
                .await
        );
        let _ = rx.recv().await; // drain the echoed Identity

        let list = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        let identity = list.devices[0].identity.as_ref().expect("identity");
        assert_eq!(identity.platform, Platform::Android as i32);
        assert_eq!(identity.device_type, DeviceType::Phone as i32);
        assert_eq!(identity.device_name, "Anil's Phone");
    }

    /// Builds a Request that looks like it arrived over a real TCP
    /// connection from the given peer address, matching what tonic's
    /// transport layer injects for `remote_addr()` to read.
    fn request_from<T>(message: T, peer: std::net::SocketAddr) -> Request<T> {
        let mut request = Request::new(message);
        request
            .extensions_mut()
            .insert(tonic::transport::server::TcpConnectInfo {
                local_addr: None,
                remote_addr: Some(peer),
            });
        request
    }

    /// Fail-closed check: local-UI RPCs deny callers with no peer
    /// address (in-process) and callers from non-loopback addresses.
    #[tokio::test]
    async fn local_rpcs_reject_non_loopback_callers() {
        let service = test_service().await;

        let no_addr = service
            .get_local_state(Request::new(GetLocalStateRequest {}))
            .await;
        assert_eq!(no_addr.unwrap_err().code(), tonic::Code::PermissionDenied);

        let remote_peer: std::net::SocketAddr = "192.168.1.50:44444".parse().unwrap();
        let remote = service
            .get_local_state(request_from(GetLocalStateRequest {}, remote_peer))
            .await;
        assert_eq!(remote.unwrap_err().code(), tonic::Code::PermissionDenied);

        let remote_stream = service
            .subscribe_local_events(request_from(LocalEventsRequest {}, remote_peer))
            .await;
        match remote_stream {
            Err(status) => assert_eq!(status.code(), tonic::Code::PermissionDenied),
            Ok(_) => panic!("non-loopback subscribe must be denied"),
        }

        let remote_disconnect = service
            .disconnect_device(request_from(
                DisconnectDeviceRequest {
                    device_id: "some-device".to_string(),
                },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_disconnect.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );

        // T-307
        let remote_forget = service
            .forget_device(request_from(
                ForgetDeviceRequest {
                    device_id: "some-device".to_string(),
                },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_forget.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );

        // T-309
        let remote_input_toggle = service
            .set_remote_input_enabled(request_from(
                SetRemoteInputEnabledRequest { enabled: false },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_input_toggle.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );

        // T-310
        let remote_clipboard_toggle = service
            .set_clipboard_sync_enabled(request_from(
                SetClipboardSyncEnabledRequest { enabled: false },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_clipboard_toggle.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );

        // Phase J
        let remote_record_history = service
            .record_transfer_history(request_from(
                RecordTransferHistoryRequest {
                    entry: Some(TransferHistoryEntry {
                        transfer_id: "t".to_string(),
                        peer_device_id: "some-device".to_string(),
                        file_name: "x.bin".to_string(),
                        total_bytes: 1,
                        direction: "outgoing".to_string(),
                        status: "completed".to_string(),
                        started_at_ms: 0,
                        finished_at_ms: 1,
                    }),
                },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_record_history.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );

        let remote_list_history = service
            .list_transfer_history(request_from(
                ListTransferHistoryRequest { limit: 10 },
                remote_peer,
            ))
            .await;
        assert_eq!(
            remote_list_history.unwrap_err().code(),
            tonic::Code::PermissionDenied
        );
    }

    /// T-307: forgetting a paired device removes it from ListDevices
    /// entirely (not merely marking it offline), and a subsequent Pair
    /// from the same device_id is no longer short-circuited by T-015 --
    /// it goes through a fresh PIN exchange exactly like a first-time
    /// pairing.
    #[tokio::test]
    async fn forget_device_removes_pairing_and_requires_a_fresh_pin_to_repair() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50002".parse().unwrap();

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");
        let pin = service.pairing.peek_pin("requester-id").expect("pin");
        service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc");

        let listed = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert_eq!(listed.devices.len(), 1, "device must be paired first");

        let response = service
            .forget_device(request_from(
                ForgetDeviceRequest {
                    device_id: "requester-id".to_string(),
                },
                loopback,
            ))
            .await
            .expect("forget_device rpc")
            .into_inner();
        assert!(
            response.removed,
            "an existing paired device must be removed"
        );

        let after = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert!(
            after.devices.is_empty(),
            "forgotten device must no longer appear in ListDevices"
        );

        // Forgetting again is a no-op, not an error.
        let repeat = service
            .forget_device(request_from(
                ForgetDeviceRequest {
                    device_id: "requester-id".to_string(),
                },
                loopback,
            ))
            .await
            .expect("forget_device rpc")
            .into_inner();
        assert!(!repeat.removed);

        // T-015's short-circuit must NOT fire anymore: re-pairing the
        // same device_id issues a fresh PIN instead of accepting
        // immediately.
        let repair = service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("re-pair rpc")
            .into_inner();
        assert!(
            repair.pin_expires_at_ms > 0,
            "a forgotten device must go through a fresh PIN exchange, not the T-015 short-circuit"
        );
    }

    /// T-102: the local UI's "Disconnect" action drops a connected
    /// peer's live-connection attribution, which is exactly what makes
    /// `ListDevices` stop reporting it online (mirrors
    /// `connected_peer_is_online_without_mdns`'s online computation, but
    /// exercised through the RPC a real caller uses).
    #[tokio::test]
    async fn disconnect_device_drops_online_attribution_for_loopback_caller() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50001".parse().unwrap();

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");
        let pin = service.pairing.peek_pin("requester-id").expect("pin");
        service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: pin,
            }))
            .await
            .expect("confirm_pin rpc");

        let (tx, _rx) = tokio::sync::mpsc::channel(4);
        let conn_id = service.peers.register(tx);
        service
            .peers
            .bind_device(conn_id, "requester-id".to_string());

        let before = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert!(before.devices[0].online, "peer must start out online");

        let response = service
            .disconnect_device(request_from(
                DisconnectDeviceRequest {
                    device_id: "requester-id".to_string(),
                },
                loopback,
            ))
            .await
            .expect("disconnect_device rpc")
            .into_inner();
        assert!(
            response.was_connected,
            "a live connection was open and should be reported found"
        );

        let after = service
            .list_devices(Request::new(ListDevicesRequest { online_only: false }))
            .await
            .expect("list_devices rpc")
            .into_inner();
        assert!(
            !after.devices[0].online,
            "device must no longer be counted online after disconnect_device"
        );

        // Disconnecting an already-disconnected device is a no-op, not
        // an error, and correctly reports nothing was found.
        let repeat = service
            .disconnect_device(request_from(
                DisconnectDeviceRequest {
                    device_id: "requester-id".to_string(),
                },
                loopback,
            ))
            .await
            .expect("disconnect_device rpc")
            .into_inner();
        assert!(!repeat.was_connected);
    }

    #[tokio::test]
    async fn get_local_state_returns_snapshot_for_loopback_caller() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50000".parse().unwrap();

        let state = service
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("loopback caller must be allowed")
            .into_inner();

        assert_eq!(
            state.local_identity.expect("identity").device_id,
            "responder-id"
        );
        assert!(state.capabilities.contains(&"file_transfer".to_string()));
        // test_service has no clipboard/input backends wired
        assert!(!state.capabilities.contains(&"clipboard".to_string()));
        assert!(state.latest_battery.is_none());
        // T-309/T-310: with no backends wired at all, both toggles read
        // as disabled rather than defaulting to true.
        assert!(!state.remote_input_enabled);
        assert!(!state.clipboard_sync_enabled);
    }

    /// T-309: toggling remote input off is reflected by GetLocalState,
    /// and the RPC is rejected outright when no input backend exists.
    #[tokio::test]
    async fn set_remote_input_enabled_requires_a_backend_and_updates_local_state() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50003".parse().unwrap();

        // test_service() wires no input backend, so toggling must fail
        // with FAILED_PRECONDITION rather than silently succeeding.
        let no_backend = service
            .set_remote_input_enabled(request_from(
                SetRemoteInputEnabledRequest { enabled: false },
                loopback,
            ))
            .await;
        assert_eq!(
            no_backend.unwrap_err().code(),
            tonic::Code::FailedPrecondition
        );

        let mut with_backend = service;
        with_backend.input = Some(Arc::new(InputDispatcher::new(Arc::new(NoopInputBackend))));

        let state_before = with_backend
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("get_local_state")
            .into_inner();
        assert!(
            state_before.remote_input_enabled,
            "a wired backend defaults to enabled"
        );

        let response = with_backend
            .set_remote_input_enabled(request_from(
                SetRemoteInputEnabledRequest { enabled: false },
                loopback,
            ))
            .await
            .expect("toggle rpc")
            .into_inner();
        assert!(!response.enabled);

        let state_after = with_backend
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("get_local_state")
            .into_inner();
        assert!(!state_after.remote_input_enabled);
    }

    /// T-310: toggling clipboard sync off is reflected by
    /// GetLocalState and gates incoming Clipboard frames in
    /// handle_frame; the RPC is rejected when no clipboard backend
    /// exists at all.
    #[tokio::test]
    async fn set_clipboard_sync_enabled_requires_a_backend_and_gates_incoming_frames() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50004".parse().unwrap();

        // test_service() wires no clipboard backend, so toggling must
        // fail with FAILED_PRECONDITION.
        let no_backend = service
            .set_clipboard_sync_enabled(request_from(
                SetClipboardSyncEnabledRequest { enabled: false },
                loopback,
            ))
            .await;
        assert_eq!(
            no_backend.unwrap_err().code(),
            tonic::Code::FailedPrecondition
        );

        let mut with_backend = service;
        with_backend.clipboard = Some(Arc::new(ClipboardSync::new(Arc::new(NoopClipboardBackend))));

        let state_before = with_backend
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("get_local_state")
            .into_inner();
        assert!(
            state_before.clipboard_sync_enabled,
            "a wired backend defaults to enabled"
        );

        let response = with_backend
            .set_clipboard_sync_enabled(request_from(
                SetClipboardSyncEnabledRequest { enabled: false },
                loopback,
            ))
            .await
            .expect("toggle rpc")
            .into_inner();
        assert!(!response.enabled);

        let state_after = with_backend
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("get_local_state")
            .into_inner();
        assert!(!state_after.clipboard_sync_enabled);

        // Disabled sync must actually gate incoming Clipboard frames --
        // handle_frame must not reach ClipboardSync::apply_incoming.
        let (tx, mut rx) = tokio::sync::mpsc::channel(4);
        let conn = with_backend.peers.register(tx.clone());
        let mut peer = String::from("peer-1");
        let incoming = crate::proto::connectible::v1::ClipboardData {
            mime_type: "text/plain".to_string(),
            content: b"should be ignored".to_vec(),
            captured_at_ms: 0,
            content_hash: "deadbeef".to_string(),
        };
        assert!(
            with_backend
                .handle_frame(Payload::Clipboard(incoming), &tx, &mut peer, conn, None)
                .await
        );
        drop(rx.try_recv()); // no frame expected either way; just drain

        let history = with_backend
            .clipboard
            .as_ref()
            .expect("clipboard wired")
            .history();
        assert!(
            history.is_empty(),
            "clipboard frame must be ignored while sync is disabled, not applied"
        );
    }

    /// T-X12: the clipboard-sync toggle survives a daemon restart. Turn
    /// it off via the RPC against a clipboard-backed service in an
    /// isolated data_dir, then rebuild the service the way lib.rs does
    /// (seed the atomic from `load_ui_toggles`) and confirm GetLocalState
    /// still reports it off -- not silently re-enabled, which was the
    /// privacy-expectation break this task fixes.
    #[tokio::test]
    async fn clipboard_sync_toggle_persists_across_a_restart() {
        let dir = tempfile::tempdir().expect("tempdir");
        let loopback: std::net::SocketAddr = "127.0.0.1:50011".parse().unwrap();
        let clipboard = Arc::new(ClipboardSync::new(Arc::new(NoopClipboardBackend)));

        let first =
            test_service_with(dir.path().to_path_buf(), Some(clipboard.clone()), true).await;
        first
            .set_clipboard_sync_enabled(request_from(
                SetClipboardSyncEnabledRequest { enabled: false },
                loopback,
            ))
            .await
            .expect("toggle off");

        // The choice is persisted to disk...
        assert!(
            !crate::config::load_ui_toggles(dir.path()).clipboard_sync_enabled,
            "toggling off must persist to the ui_toggles file"
        );

        // ...and a freshly-built service seeded from that file (as lib.rs
        // does at startup) still reports it off.
        let reloaded = crate::config::load_ui_toggles(dir.path());
        let restarted = test_service_with(
            dir.path().to_path_buf(),
            Some(clipboard),
            reloaded.clipboard_sync_enabled,
        )
        .await;
        let state = restarted
            .get_local_state(request_from(GetLocalStateRequest {}, loopback))
            .await
            .expect("get_local_state")
            .into_inner();
        assert!(
            !state.clipboard_sync_enabled,
            "clipboard sync must stay off after a restart, not silently re-enable"
        );
    }

    /// T-014/T-036 end-to-end at the handler level: a UI subscribed to
    /// local events sees the pairing prompt (with the PIN) the moment a
    /// remote PairRequest arrives, and that PIN verifies via ConfirmPin.
    #[tokio::test]
    async fn subscribe_local_events_delivers_pairing_prompt_with_working_pin() {
        let service = test_service().await;
        let loopback: std::net::SocketAddr = "127.0.0.1:50001".parse().unwrap();

        let mut events = service
            .subscribe_local_events(request_from(LocalEventsRequest {}, loopback))
            .await
            .expect("loopback subscribe")
            .into_inner();

        service
            .pair(Request::new(PairRequest {
                requester: Some(requester_identity()),
            }))
            .await
            .expect("pair rpc");

        let event = tokio::time::timeout(std::time::Duration::from_secs(2), events.next())
            .await
            .expect("event within 2s")
            .expect("stream not ended")
            .expect("no stream error");

        let Some(local_event::Event::PairingRequested(prompt)) = event.event else {
            panic!("expected a PairingRequested event");
        };
        assert_eq!(prompt.requester_device_id, "requester-id");
        assert_eq!(prompt.pin_code.len(), 6);

        let confirm = service
            .confirm_pin(Request::new(ConfirmPinRequest {
                device_id: "requester-id".to_string(),
                pin_code: prompt.pin_code,
            }))
            .await
            .expect("confirm_pin rpc")
            .into_inner();
        assert!(confirm.verified, "PIN from the local event must verify");
    }
}
