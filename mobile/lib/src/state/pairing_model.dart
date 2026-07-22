import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../models/models.dart';
import '../services/connectible_exception.dart';
import '../services/connectible_server.dart';
import '../services/grpc_service.dart';
import '../services/pairing_manager.dart';
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
    required void Function(pb.FileTransferStart) onFileTransferStart,
    required void Function(pb.FileChunk) onFileChunk,
    required void Function(pb.FileChunkRequest) onFileChunkRequest,
    Future<pb.PrepareUploadResponse> Function(pb.PrepareUploadRequest)?
        onPrepareUpload,
    Future<pb.UploadFileResult> Function(Stream<pb.UploadFilePart>)?
        onUploadFile,
    bool pairableEnabled = true,
  })  : _deviceList = deviceList,
        _onClipboardFrame = onClipboardFrame,
        _onFileTransferStart = onFileTransferStart,
        _onFileChunk = onFileChunk,
        _onFileChunkRequest = onFileChunkRequest,
        _onPrepareUpload = onPrepareUpload,
        _onUploadFile = onUploadFile,
        _pairableEnabled = pairableEnabled {
    if (_pairableEnabled) {
      unawaited(_startServer());
    }
  }

  final DeviceListModel _deviceList;
  final void Function(pb.ClipboardData) _onClipboardFrame;
  final void Function(pb.FileTransferStart) _onFileTransferStart;
  final void Function(pb.FileChunk) _onFileChunk;
  final void Function(pb.FileChunkRequest) _onFileChunkRequest;
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
  String? lastError;

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

  @override
  String? get activePeerId => _activePeer?.deviceId;

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

  Future<void> _startServer() async {
    if (_server != null) return;
    try {
      final identity = await ServerIdentity.loadOrCreate();
      final server = ConnectibleServer(this, _pairing);
      await server.start(identity);
      _server = server;
    } catch (e) {
      debugPrint('inbound server failed to start: $e');
    }
  }

  /// Applies the Settings screen's "allow this phone to be paired into"
  /// toggle (T-308) live: stops the inbound `ConnectibleServer` and its
  /// mDNS advertisement immediately when disabled, restarts both
  /// immediately when re-enabled. The persisted `SettingsModel` value is
  /// what makes this stick across the next app launch.
  Future<void> setPairableEnabled(bool enabled) async {
    if (enabled == _pairableEnabled) return;
    _pairableEnabled = enabled;
    _deviceList.setPairableEnabled(enabled);
    if (enabled) {
      await _startServer();
    } else {
      final server = _server;
      _server = null;
      await server?.stop();
    }
    notifyListeners();
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
    // is TOFU, Phase C). Reject before any bytes move.
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

  @override
  Stream<pb.SyncFrame> onInboundSyncStream(Stream<pb.SyncFrame> inbound) {
    // A desktop peer opened a SyncStream to this phone. Route its frames
    // through the same handler used for the outgoing path, and hand back
    // an outbound channel so clipboard/file features work both ways.
    unawaited(_inboundServerOut?.close());
    final out = StreamController<pb.SyncFrame>();
    _inboundServerOut = out;
    _outbound = out;
    out.add(pb.SyncFrame(identity: localIdentity));

    inbound.listen(
      _onInboundFrame,
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

  void _closeInboundSession() {
    final out = _inboundServerOut;
    _inboundServerOut = null;
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
      final grpc = await GrpcService.connect(device.host, device.port);
      final outcome = await grpc.pair(localIdentity);
      if (!outcome.accepted) {
        await grpc.shutdown();
        lastError = 'Pairing was rejected';
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
    } on ConnectibleException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = '$e';
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

      await _activate(pairing.grpc);
      _activePeer = pairing.device;
      pendingPairing = null;
      await refreshDevices();
      // TOFU (T-C2): pin the cert we just saw as this peer's trust anchor.
      // Best-effort -- a no-op if the requester side didn't persist the peer
      // to the paired store; the next reconnect backfills it either way.
      final observed = pairing.grpc.observedFingerprint;
      if (observed != null) {
        _deviceList.recordFingerprint(pairing.device.deviceId, observed);
      }
      notifyListeners();
      return true;
    } on ConnectibleException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = '$e';
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
      case pb.SyncFrame_Payload.fileTransferStart:
        _onFileTransferStart(frame.fileTransferStart);
        break;
      case pb.SyncFrame_Payload.fileChunk:
        _onFileChunk(frame.fileChunk);
        break;
      case pb.SyncFrame_Payload.fileChunkRequest:
        _onFileChunkRequest(frame.fileChunkRequest);
        break;
      default:
        // Other frame kinds (battery/notification/etc.) are not shown on
        // mobile in the MVP.
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
        Timer(Duration(seconds: delaySeconds), () => _reconnect(peer));
  }

  Future<void> _reconnect(NearbyDevice peer) async {
    if (_intentionalDisconnect) return;
    // TOFU (T-C4): require the peer's pinned cert. `_activate` opens the
    // SyncStream, which is what actually triggers the TLS handshake and the
    // pin check.
    final pinned = _deviceList.pinnedFingerprint(peer.deviceId);
    GrpcService? grpc;
    try {
      grpc = await GrpcService.connect(peer.host, peer.port,
          pinnedFingerprint: pinned);
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
        lastError =
            "This device's security key changed since pairing. Forget and re-pair it to reconnect.";
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
