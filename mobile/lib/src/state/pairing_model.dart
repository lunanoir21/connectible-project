import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../models/models.dart';
import '../services/connectible_exception.dart';
import '../services/connectible_server.dart';
import '../services/grpc_service.dart';
import '../services/pairing_manager.dart';
import '../services/receiving_service.dart';
import '../services/reconnect_backoff.dart';
import '../services/server_identity.dart';
import 'device_list_model.dart';
import 'sync_connection.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

/// Requester-side pairing in progress: the connection used to reach the
/// responder plus the countdown deadline.
class RequesterPairing {
  RequesterPairing(
      {required this.device, required this.pinExpiresAtMs, required this.grpc});
  final NearbyDevice device;
  final int pinExpiresAtMs;
  final GrpcService grpc;
}

/// Categorizes [PairingModel.lastError] so the UI can pick a dedicated,
/// localized message for security-relevant failures instead of surfacing
/// the raw (English) transport/peer string. Only the model layer -- which
/// has no `BuildContext`/i18n -- assigns these; the widget layer maps them
/// to translated strings (T-X19).
enum PairingErrorKind {
  /// A connect/pairing failure whose stored [PairingModel.lastError] text
  /// is the best thing to show as-is.
  generic,

  /// A paired peer's TLS certificate changed since pairing, so a reconnect
  /// was refused (MITM-or-reinstall). The UI shows its own dedicated,
  /// actionable "forget and re-pair" string rather than the raw message.
  fingerprintChanged,

  /// The responder declined the pairing request (T-X32). Distinct from
  /// `generic` so the UI can show a translated string instead of the
  /// model's hardcoded English "Pairing was rejected".
  rejected,
}

/// Owns the pairing flow -- both requester side (dialing a discovered
/// peer, submitting the PIN it shows) and responder side (the inbound
/// `ConnectibleServer`/`PairingManager` a remote peer dials into this
/// phone) -- plus the active paired session's lifecycle (T-204): opening
/// the bidirectional SyncStream, heartbeat/reconnect, and dispatching
/// inbound frames to [ClipboardModel]/[FileTransferModel] via the
/// callbacks supplied at construction. Implements [SyncConnection] so
/// those two models can push outbound frames without depending on this
/// class concretely.
///
/// Depends on [DeviceListModel] (one-directional: reads `localIdentity`,
/// persists newly-paired peers, merges the session's device list) but
/// nothing depends back on this class from that side, avoiding a cycle.
class PairingModel extends ChangeNotifier
    implements ServerDelegate, SyncConnection {
  PairingModel({
    required DeviceListModel deviceList,
    required void Function(pb.ClipboardData) onClipboardFrame,
    // T-K4: inbound notification frames (a dismiss command from the
    // paired peer). Optional, unlike onClipboardFrame, because not every
    // caller needs it wired (e.g. tests that don't exercise notification
    // sync); a null callback silently drops the frame, same as before
    // this feature existed.
    void Function(pb.NotificationData)? onNotificationFrame,
    Future<pb.PrepareUploadResponse> Function(pb.PrepareUploadRequest)?
        onPrepareUpload,
    Future<pb.UploadFileResult> Function(Stream<pb.UploadFilePart>)?
        onUploadFile,
    bool pairableEnabled = true,
    // Injectable so unit tests can supply a pre-generated identity
    // (`ServerIdentity.generate()`, no disk I/O) instead of the real
    // `ServerIdentity.loadOrCreate()`, which needs `path_provider` --
    // unavailable in this unit test host (see `pairing_model_test.dart`).
    // Every outbound connect (`startPair`/`reconnectToPeer`, Phase G,
    // T-G6) goes through this, not just the inbound server, so it must
    // be overridable independently of `pairableEnabled`.
    Future<ServerIdentity> Function()? ownIdentityLoader,
    // T-X36: injectable so tests can fake it instead of touching a real
    // platform channel (mirrors the `NotificationListener`/
    // `SyncConnection` seam pattern already used elsewhere).
    ReceivingService receivingService = const PlatformReceivingService(),
    // Overridable so tests can bind an ephemeral port (0) instead of the
    // real, fixed `kServerPort` -- exercising `setPairableEnabled`'s full
    // start/stop path (including the receiving-service wiring above)
    // would otherwise risk colliding with another test or a real running
    // daemon on the well-known port.
    int? serverPort,
  })  : _deviceList = deviceList,
        _onClipboardFrame = onClipboardFrame,
        _onNotificationFrame = onNotificationFrame,
        _onPrepareUpload = onPrepareUpload,
        _onUploadFile = onUploadFile,
        _pairableEnabled = pairableEnabled,
        _ownIdentityLoader = ownIdentityLoader ?? ServerIdentity.loadOrCreate,
        _receivingService = receivingService,
        _serverPort = serverPort ?? kServerPort {
    if (_pairableEnabled) {
      unawaited(_startServer());
    }
  }

  final DeviceListModel _deviceList;
  final int _serverPort;
  final void Function(pb.ClipboardData) _onClipboardFrame;
  final void Function(pb.NotificationData)? _onNotificationFrame;
  final Future<pb.PrepareUploadResponse> Function(pb.PrepareUploadRequest)?
      _onPrepareUpload;
  final Future<pb.UploadFileResult> Function(Stream<pb.UploadFilePart>)?
      _onUploadFile;

  // --- inbound (responder) server: lets a desktop peer initiate pairing
  // and sync *to* this phone, making connection bidirectional. -----------
  final PairingManager _pairing = PairingManager();
  ConnectibleServer? _server;
  StreamController<pb.SyncFrame>? _inboundServerOut;

  /// Mirrors `SettingsModel.pairableEnabled` (T-308): whether the inbound
  /// `ConnectibleServer` is allowed to run at all. Set at construction
  /// from the persisted setting; toggled live via [setPairableEnabled].
  bool _pairableEnabled;
  bool get pairableEnabled => _pairableEnabled;

  /// Fires when a remote peer initiates pairing to this phone, so the UI
  /// can show the responder PIN sheet.
  Stream<PairingRequestedEvent> get incomingPairings => _pairing.events;

  @override
  pb.Identity get localIdentity => _deviceList.localIdentity;

  @override
  bool connected = false;

  /// True while an unexpected drop is being retried (distinct from the
  /// first-ever connect), so the UI can say "Reconnecting" not "Connecting".
  bool reconnecting = false;
  RequesterPairing? pendingPairing;

  /// Human-readable detail of the most recent connect/pairing failure, or
  /// null if the last attempt cleared it. [lastErrorKind] categorizes it
  /// and [lastErrorSeq] lets a listener detect a *fresh* failure.
  String? lastError;

  /// What kind of failure [lastError] describes, so the UI can localize
  /// security-relevant cases specially (see [PairingErrorKind]).
  PairingErrorKind lastErrorKind = PairingErrorKind.generic;

  /// Bumped every time a new error is recorded (via [_setError]), even when
  /// the message text is identical to the previous one, so a UI listener
  /// can reliably tell one failure from the next. Clearing [lastError] to
  /// null at the start of a fresh attempt deliberately does NOT bump this
  /// -- a clear is not something to surface.
  int lastErrorSeq = 0;

  /// Records a failure for the UI to surface. Does not call
  /// [notifyListeners]; every call site already notifies right after (kept
  /// that way so the existing flow is unchanged).
  void _setError(String message,
      {PairingErrorKind kind = PairingErrorKind.generic}) {
    lastError = message;
    lastErrorKind = kind;
    lastErrorSeq++;
  }

  GrpcService? _grpc;
  StreamController<pb.SyncFrame>? _outbound;
  StreamSubscription<pb.SyncFrame>? _inboundSub;

  // --- reconnect / liveness state -------------------------------------
  /// The peer the active session is (or was) connected to, so a dropped
  /// SyncStream can be re-established automatically.
  NearbyDevice? _activePeer;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  // T-X24: an inbound-only session (this phone as responder, e.g. a
  // desktop pushed a file with no prior outbound dial from here) never
  // sets `_activePeer` -- only `_inboundPeerDeviceId`, tracked by
  // `_onInboundFrameFromRemotePeer` above. Without this fallback,
  // `_recordHistory`'s `_connection.activePeerId` read the empty string
  // for every inbound push, so history rows for received files could
  // never resolve a peer name.
  @override
  String? get activePeerId => _activePeer?.deviceId ?? _inboundPeerDeviceId;

  /// Whether this phone's inbound gRPC/TLS server is currently bound and
  /// accepting connections (T-F9). Gated by [pairableEnabled]; used by the
  /// mobile Doctor to check the phone is reachable by peers.
  bool get serverRunning => _server != null;

  /// Display name of the peer the active session is connected to, so the
  /// transfers screen can show who a file will be sent to. Null when no
  /// session is active.
  String? get activePeerName => _activePeer?.deviceName;

  @override
  pb.ConnectibleClient? get uploadClient => _grpc?.raw;

  /// Set when the user deliberately disconnects, so an expected teardown
  /// is not mistaken for a drop and does not trigger auto-reconnect.
  bool _intentionalDisconnect = false;

  // --- inbound server (responder role) ---------------------------------

  /// This device's own cert/key identity, cached after first load
  /// (Phase G, T-G6): used both as the inbound server's TLS identity
  /// (below) and, symmetrically, as the outbound client identity every
  /// [GrpcService.connect] call presents (`startPair`/`reconnectToPeer`)
  /// -- one identity per device, either role.
  ServerIdentity? _ownIdentity;
  final Future<ServerIdentity> Function() _ownIdentityLoader;

  Future<ServerIdentity> _loadOwnIdentity() async {
    return _ownIdentity ??= await _ownIdentityLoader();
  }

  // --- receiving-role foreground service (T-X36) ------------------------
  // Keeps the inbound server + mDNS advertise + heartbeat alive under
  // Doze/OEM background kills while pairable is on -- a reliability aid,
  // not a correctness requirement (everything above still works without
  // it, just less reliably backgrounded). English defaults are used for
  // the constructor's own auto-start (no BuildContext/i18n exists that
  // early); [setPairableEnabled]'s callers (Home, Settings) pass the
  // real localized strings, and [refreshReceivingNotification] lets a
  // freshly-built screen correct an already-running notification's
  // language without needing to toggle the setting itself.
  final ReceivingService _receivingService;
  static const _defaultNotifTitle = 'Discoverable';
  static const _defaultNotifText =
      'Other devices can find this phone and send it files.';

  Future<void> _startServer({String? notifTitle, String? notifText}) async {
    if (_server != null) return;
    try {
      final identity = await _loadOwnIdentity();
      final server = ConnectibleServer(this, _pairing);
      await server.start(identity, port: _serverPort);
      _server = server;
      unawaited(_receivingService.start(
        notifTitle ?? _defaultNotifTitle,
        notifText ?? _defaultNotifText,
      ));
    } catch (e) {
      debugPrint('inbound server failed to start: $e');
    }
  }

  /// Applies the Settings screen's "allow this phone to be paired into"
  /// toggle (T-308) live: stops the inbound `ConnectibleServer` and its
  /// mDNS advertisement immediately when disabled, restarts both
  /// immediately when re-enabled. The persisted `SettingsModel` value is
  /// what makes this stick across the next app launch. [notifTitle]/
  /// [notifText] should be the caller's localized `home.receivingTitle`/
  /// `home.receivingOnHint` strings (T-X36); omitted only by callers with
  /// no i18n access (falls back to English).
  Future<void> setPairableEnabled(bool enabled,
      {String? notifTitle, String? notifText}) async {
    if (enabled == _pairableEnabled) return;
    _pairableEnabled = enabled;
    _deviceList.setPairableEnabled(enabled);
    if (enabled) {
      await _startServer(notifTitle: notifTitle, notifText: notifText);
    } else {
      final server = _server;
      _server = null;
      await server?.stop();
      unawaited(_receivingService.stop());
    }
    notifyListeners();
  }

  /// Re-posts the receiving notification with fresh (localized) text if
  /// the server is currently running (T-X36) -- called once from Home so
  /// a notification started in English (the constructor's auto-start, or
  /// a locale change since) catches up without the user toggling the
  /// setting off and back on.
  void refreshReceivingNotification(String title, String text) {
    if (_server == null) return;
    unawaited(_receivingService.start(title, text));
  }

  @override
  void onPeerPaired(pb.Identity requester) {
    _deviceList.addPairedDevice(requester);
  }

  @override
  List<DeviceInfo> knownDevices() => _deviceList.knownDevices();

  @override
  Future<pb.PrepareUploadResponse> prepareUpload(
      pb.PrepareUploadRequest request) async {
    // Only a paired device may push files (same trust level as the rest
    // of the app, keyed on the claimed device_id; per-device cert binding
    // is TOFU, Phase C -- mobile's responder side has no TLS-layer
    // client-cert verification, see the note in
    // `ConnectibleServer.start`). Reject before any bytes move.
    final senderId = request.sender.deviceId;
    final paired =
        _deviceList.knownDevices().any((d) => d.deviceId == senderId);
    if (!paired) {
      throw const GrpcError.unauthenticated('device is not paired');
    }
    final handler = _onPrepareUpload;
    if (handler == null) {
      throw const GrpcError.unimplemented('file upload receive not wired');
    }
    return handler(request);
  }

  @override
  Future<pb.UploadFileResult> uploadFile(Stream<pb.UploadFilePart> request) {
    final handler = _onUploadFile;
    if (handler == null) {
      throw const GrpcError.unimplemented('file upload receive not wired');
    }
    return handler(request);
  }

  // Phase G, T-G6: the device_id the *current inbound* session's peer
  // claimed via its Identity frame (previously silently dropped --
  // `onInboundSyncStream` never tracked it at all, so non-Identity
  // frames were processed with no pairing check whatsoever). Gated in
  // `_onInboundFrameFromRemotePeer` below. Fingerprint-level connection
  // binding (matching the daemon's `handle_frame`) was attempted and
  // reverted -- see the note in `ConnectibleServer.start`: `dart:io`'s
  // `SecureServerSocket` cannot accept an unverified self-signed client
  // certificate, so mobile's responder role has no TLS-layer identity
  // to check against. Only the inbound (responder) path needs this
  // tracking -- the outbound (requester) path's peer is already
  // TOFU-verified at the TLS layer by the time this device chose to
  // dial out (`GrpcService.connect`'s `_TofuState`), so `_activate`
  // below reuses the shared, ungated `_onInboundFrame` directly.
  String? _inboundPeerDeviceId;

  @override
  Stream<pb.SyncFrame> onInboundSyncStream(Stream<pb.SyncFrame> inbound) {
    // A desktop peer opened a SyncStream to this phone. Route its frames
    // through the same handler used for the outgoing path, and hand back
    // an outbound channel so clipboard/file features work both ways.
    unawaited(_inboundServerOut?.close());
    final out = StreamController<pb.SyncFrame>();
    _inboundServerOut = out;
    _outbound = out;
    _inboundPeerDeviceId = null;
    out.add(pb.SyncFrame(identity: localIdentity));

    inbound.listen(
      _onInboundFrameFromRemotePeer,
      onError: (Object e) {
        debugPrint('inbound sync stream error: $e');
        _closeInboundSession();
      },
      onDone: _closeInboundSession,
      cancelOnError: true,
    );

    connected = true;
    reconnecting = false;
    notifyListeners();
    return out.stream;
  }

  /// Phase G, T-G6: gates every non-`Identity` frame arriving on the
  /// *inbound* (responder) SyncStream on the claimed device_id being
  /// paired -- closing the real, pre-existing gap where inbound frames
  /// were processed with no pairing check at all. `Identity` itself is
  /// exempt -- it is what lets a fresh inbound connection attribute
  /// itself in the first place. Fail closed: a frame arriving before any
  /// `Identity` frame, or an unpaired claimed device_id, is dropped
  /// silently -- mobile's SyncStream has no error-frame convention
  /// symmetric to the daemon's `send_error`, so rejection here is a
  /// drop, not a reply.
  ///
  /// This does *not* verify the connection's TLS identity against the
  /// claimed device_id the way the daemon's `handle_frame` does (T-G5) --
  /// see the note in `ConnectibleServer.start` for why that is not
  /// achievable on mobile's responder side with `dart:io`. A device that
  /// somehow learned a paired peer's device_id could still claim it
  /// here; this closes the "no check at all" gap, not the full
  /// spoofing gap the daemon closes.
  void _onInboundFrameFromRemotePeer(pb.SyncFrame frame) {
    if (frame.whichPayload() == pb.SyncFrame_Payload.identity) {
      _inboundPeerDeviceId = frame.identity.deviceId;
      return;
    }
    final peerId = _inboundPeerDeviceId;
    if (peerId == null || peerId.isEmpty) {
      debugPrint('rejecting inbound frame: peer has not identified itself yet');
      return;
    }
    final paired = _deviceList.knownDevices().any((d) => d.deviceId == peerId);
    if (!paired) {
      debugPrint('rejecting inbound frame from unpaired/unidentified peer: $peerId');
      return;
    }
    _onInboundFrame(frame);
  }

  void _closeInboundSession() {
    final out = _inboundServerOut;
    _inboundServerOut = null;
    _inboundPeerDeviceId = null;
    if (identical(_outbound, out)) {
      _outbound = null;
    }
    unawaited(out?.close());
    // Only drop the connected flag if no outgoing session is active.
    if (_grpc == null) {
      connected = false;
    }
    notifyListeners();
  }

  // --- pairing (requester side) ----------------------------------------

  /// Connects to [device] and asks it to show its PIN dialog. On success
  /// [pendingPairing] is set and the UI shows the PIN entry sheet.
  Future<bool> startPair(NearbyDevice device) async {
    lastError = null;
    try {
      final identity = await _loadOwnIdentity();
      final grpc =
          await GrpcService.connect(device.host, device.port, identity: identity);
      final outcome = await grpc.pair(localIdentity);
      if (!outcome.accepted) {
        await grpc.shutdown();
        _setError('Pairing was rejected', kind: PairingErrorKind.rejected);
        notifyListeners();
        return false;
      }
      pendingPairing = RequesterPairing(
        device: device,
        pinExpiresAtMs: outcome.pinExpiresAtMs,
        grpc: grpc,
      );
      notifyListeners();
      return true;
    } on FingerprintChangedException catch (e) {
      // T-X33: the daemon-side (not just mobile's own local TOFU check)
      // fingerprint mismatch also gets the same dedicated, actionable
      // string as the client-side case, instead of collapsing to the
      // raw peer message.
      _setError(e.message, kind: PairingErrorKind.fingerprintChanged);
      notifyListeners();
      return false;
    } on ConnectibleException catch (e) {
      _setError(e.message);
      notifyListeners();
      return false;
    } catch (e) {
      _setError('$e');
      notifyListeners();
      return false;
    }
  }

  /// Submits the PIN the user read off the computer's screen. On success
  /// the connection is promoted to the active paired session.
  Future<bool> confirmPin(String pin) async {
    final pairing = pendingPairing;
    if (pairing == null) return false;
    try {
      final verified =
          await pairing.grpc.confirmPin(localIdentity.deviceId, pin);
      if (!verified) return false;

      // T-X1: persist the peer on the requester side too, symmetric with
      // the responder path's onPeerPaired -- the responder has already
      // recorded us at this point. Without this, a phone-initiated pairing
      // vanished on restart, desktop->phone pushes were rejected (the
      // prepareUpload/inbound-frame gates read the paired store), and the
      // TOFU pin below silently no-opped. Must run BEFORE recordFingerprint
      // so the pin has a store row to land on (T-X2).
      _deviceList.addPairedDeviceFromNearby(pairing.device);

      await _activate(pairing.grpc);
      _activePeer = pairing.device;
      pendingPairing = null;
      await refreshDevices();
      // TOFU (T-C2): pin the cert we just saw as this peer's trust anchor.
      // The paired-store row was just written above, so the pin lands
      // immediately; a reconnect backfills it if the fingerprint was
      // somehow unavailable here.
      final observed = pairing.grpc.observedFingerprint;
      if (observed != null) {
        _deviceList.recordFingerprint(pairing.device.deviceId, observed);
      }
      notifyListeners();
      return true;
    } on FingerprintChangedException catch (e) {
      // T-X33: the daemon-side (not just mobile's own local TOFU check)
      // fingerprint mismatch also gets the same dedicated, actionable
      // string as the client-side case, instead of collapsing to the
      // raw peer message.
      _setError(e.message, kind: PairingErrorKind.fingerprintChanged);
      notifyListeners();
      return false;
    } on ConnectibleException catch (e) {
      _setError(e.message);
      notifyListeners();
      return false;
    } catch (e) {
      _setError('$e');
      notifyListeners();
      return false;
    }
  }

  void cancelPairing() {
    pendingPairing?.grpc.shutdown();
    pendingPairing = null;
    notifyListeners();
  }

  // --- active connection + sync stream ---------------------------------

  Future<void> _activate(GrpcService grpc) async {
    await _teardownConnection();
    _intentionalDisconnect = false;
    _grpc = grpc;

    final outbound = StreamController<pb.SyncFrame>();
    _outbound = outbound;

    // Identify ourselves first, then keep the stream open.
    outbound.add(pb.SyncFrame(identity: localIdentity));

    _inboundSub = grpc.openSyncStream(outbound.stream).listen(
      _onInboundFrame,
      onError: (Object e) {
        debugPrint('sync stream error: $e');
        _handleConnectionLost();
      },
      onDone: _handleConnectionLost,
    );
    connected = true;
    reconnecting = false;
    _startHeartbeat();
    notifyListeners();
  }

  void _onInboundFrame(pb.SyncFrame frame) {
    switch (frame.whichPayload()) {
      case pb.SyncFrame_Payload.clipboard:
        _onClipboardFrame(frame.clipboard);
        break;
      case pb.SyncFrame_Payload.notification:
        // T-K4: only a dismiss command is meaningful inbound here -- see
        // NotificationModel.handleInbound's own doc for why.
        _onNotificationFrame?.call(frame.notification);
        break;
      default:
        // File transfer now runs entirely over the dedicated
        // PrepareUpload/UploadFile RPCs (Phase I), not SyncFrame
        // payloads, so fileTransferStart/fileChunk/fileChunkRequest are
        // no longer dispatched here. Battery is not shown on mobile in
        // the MVP.
        break;
    }
  }

  // --- connection liveness + auto-reconnect ----------------------------

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final grpc = _grpc;
      if (grpc == null) return;
      try {
        await grpc.pingRttMs();
      } catch (e) {
        debugPrint('heartbeat ping failed: $e');
        _handleConnectionLost();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Handles an unexpected drop: claims `_grpc` synchronously so a racing
  /// detector (stream onDone + heartbeat) cannot double-handle, tears the
  /// dead connection down, and schedules an automatic reconnect.
  void _handleConnectionLost() {
    final grpc = _grpc;
    if (_intentionalDisconnect || grpc == null) return;
    _grpc = null;
    connected = false;
    _stopHeartbeat();
    unawaited(_inboundSub?.cancel());
    _inboundSub = null;
    unawaited(_outbound?.close());
    _outbound = null;
    unawaited(grpc.shutdown());
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final peer = _activePeer;
    if (_intentionalDisconnect || peer == null) return;
    _reconnectTimer?.cancel();
    reconnecting = true;
    final delaySeconds = reconnectBackoffSeconds(_reconnectAttempt);
    _reconnectAttempt++;
    notifyListeners();
    _reconnectTimer =
        Timer(Duration(seconds: delaySeconds), () => reconnectToPeer(peer));
  }

  /// Resumes a session with an already-paired device -- either
  /// automatically after an unexpected drop ([_scheduleReconnect]'s
  /// timer), or manually, when the user taps "Connect" on a paired
  /// device that's showing offline but was rediscovered via mDNS
  /// (home_screen.dart's device action sheet). No PIN needed: the TOFU-
  /// pinned cert from the original pairing is what authenticates this
  /// peer, not a fresh code exchange.
  Future<void> reconnectToPeer(NearbyDevice peer) async {
    if (_intentionalDisconnect) return;
    // TOFU (T-C4): require the peer's pinned cert. `_activate` opens the
    // SyncStream, which is what actually triggers the TLS handshake and the
    // pin check.
    final pinned = _deviceList.pinnedFingerprint(peer.deviceId);
    GrpcService? grpc;
    try {
      final identity = await _loadOwnIdentity();
      grpc = await GrpcService.connect(peer.host, peer.port,
          identity: identity, pinnedFingerprint: pinned);
      // Already paired, so no PIN dance: re-opening the SyncStream and
      // re-sending Identity is enough for the daemon to resume the peer.
      await _activate(grpc);
      // Record-on-first-use / backfill (T-C5) once the handshake succeeded.
      final observed = grpc.observedFingerprint;
      if (pinned == null && observed != null) {
        _deviceList.recordFingerprint(peer.deviceId, observed);
      }
      _activePeer = peer;
      _reconnectAttempt = 0;
      await refreshDevices();
    } catch (e) {
      // A changed cert is not a transient failure: stop retrying and
      // surface it, since only a forget+re-pair can resolve it.
      if (grpc != null && grpc.fingerprintMismatch) {
        debugPrint('reconnect blocked: peer certificate changed');
        // The user-visible copy comes from an i18n key on Home
        // (`home.fingerprintChanged`), keyed off [PairingErrorKind]; this
        // English fallback is only for any non-UI reader of [lastError].
        _setError(
          "This device's security key changed since pairing. Forget and re-pair it to reconnect.",
          kind: PairingErrorKind.fingerprintChanged,
        );
        _activePeer = null;
        reconnecting = false;
        notifyListeners();
        return;
      }
      debugPrint('reconnect failed: $e');
      _scheduleReconnect();
    }
  }

  /// User-initiated disconnect from the active session; unlike an
  /// unexpected drop this stops any reconnect attempts.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _activePeer = null;
    await _teardownConnection();
    connected = false;
    reconnecting = false;
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    final grpc = _grpc;
    if (grpc == null) return;
    try {
      _deviceList.mergeFromConnection(await grpc.listDevices());
    } catch (e) {
      debugPrint('listDevices failed: $e');
    }
  }

  // --- SyncConnection (used by ClipboardModel / FileTransferModel) -----

  @override
  void sendFrame(pb.SyncFrame frame) {
    _outbound?.add(frame);
  }

  // --- input session ----------------------------------------------------

  /// Sends one remote input event over the active stream. Coordinates
  /// are normalized [0,1] per the wire contract.
  void sendPointerMove(double x, double y) {
    sendFrame(pb.SyncFrame(
      inputEvent: pb.RemoteInputEvent(
        type: pb.InputEventType.INPUT_EVENT_TYPE_MOUSE_MOVE,
        x: x,
        y: y,
      ),
    ));
  }

  void sendMouseButton(pb.MouseButton button, bool pressed) {
    sendFrame(pb.SyncFrame(
      inputEvent: pb.RemoteInputEvent(
        type: pb.InputEventType.INPUT_EVENT_TYPE_MOUSE_BUTTON,
        button: button,
        pressed: pressed,
      ),
    ));
  }

  /// Two-finger scroll (T-305). Deltas follow `RemoteInputEvent`'s wire
  /// contract: positive = scroll up/right.
  void sendScroll(double deltaX, double deltaY) {
    sendFrame(pb.SyncFrame(
      inputEvent: pb.RemoteInputEvent(
        type: pb.InputEventType.INPUT_EVENT_TYPE_MOUSE_SCROLL,
        scrollDeltaX: deltaX,
        scrollDeltaY: deltaY,
      ),
    ));
  }

  /// [modifiers] is the wire's bit mask (1=shift, 2=ctrl, 4=alt, 8=meta),
  /// defaulting to none for plain character keys.
  void sendKey(int keyCode, bool pressed, {int modifiers = 0}) {
    sendFrame(pb.SyncFrame(
      inputEvent: pb.RemoteInputEvent(
        type: pb.InputEventType.INPUT_EVENT_TYPE_KEY,
        keyCode: keyCode,
        keyPressed: pressed,
        modifiers: modifiers,
      ),
    ));
  }

  // --- teardown ---------------------------------------------------------

  Future<void> _teardownConnection() async {
    _stopHeartbeat();
    await _inboundSub?.cancel();
    await _outbound?.close();
    await _grpc?.shutdown();
    _inboundSub = null;
    _outbound = null;
    _grpc = null;
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    unawaited(_server?.stop());
    _pairing.dispose();
    unawaited(_inboundServerOut?.close());
    _teardownConnection();
    super.dispose();
  }
}
