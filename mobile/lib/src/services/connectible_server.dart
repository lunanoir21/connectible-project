import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../generated/connectible.pbgrpc.dart' as pb;
import '../models/models.dart';
import 'connectible_exception.dart';
import 'pairing_manager.dart';
import 'server_identity.dart';

/// Port this device listens on, matching the mDNS advertisement in
/// `MdnsService` and the daemon's default gRPC port.
const int kServerPort = 58231;

/// [ServerTlsCredentials] pins `minimumTlsProtocolVersion` to TLS 1.3
/// (T-401), matching the daemon's hand-built rustls `ServerConfig`
/// (daemon/src/tls.rs) which restricts to TLS 1.3 only. Dart's
/// `SecurityContext.minimumTlsProtocolVersion` (available since this
/// SDK) lets a client that only offers TLS 1.2 be rejected at the
/// handshake, rather than only advertising cert/key with no version
/// floor as before.
class Tls13OnlyServerCredentials extends ServerTlsCredentials {
  Tls13OnlyServerCredentials({
    required super.certificate,
    required super.privateKey,
  });

  @override
  SecurityContext get securityContext {
    final context = super.securityContext;
    context.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
    return context;
  }
}

/// Callbacks the [ConnectibleServer] uses to reach app state without a
/// hard dependency on [PairingModel]. Keeps the gRPC plumbing testable.
abstract class ServerDelegate {
  /// A remote peer completed pairing (entered the correct PIN). Persist
  /// it as a known paired device.
  void onPeerPaired(pb.Identity requester);

  /// Paired devices to report to a peer's ListDevices call.
  List<DeviceInfo> knownDevices();

  /// This device's own identity, echoed to peers.
  pb.Identity get localIdentity;

  /// A remote peer opened a SyncStream to this device (we are the
  /// responder). [inbound] carries frames from the peer; the returned
  /// stream carries frames back. Called at most once per active peer
  /// connection; a new call supersedes any previous inbound session.
  Stream<pb.SyncFrame> onInboundSyncStream(Stream<pb.SyncFrame> inbound);

  /// Responder side of the dedicated file upload (TASKS.md Phase A):
  /// authorize the sender + report accept/resume/token per file.
  Future<pb.PrepareUploadResponse> prepareUpload(pb.PrepareUploadRequest request);

  /// Responder side of `UploadFile`: consume the client byte stream and
  /// return the final result.
  Future<pb.UploadFileResult> uploadFile(Stream<pb.UploadFilePart> request);
}

/// gRPC server exposing the [pb.ConnectibleServiceBase] surface a desktop
/// peer needs to initiate pairing and sync *to* this phone -- the missing
/// half that makes connection bidirectional (KDE-Connect style). The
/// loopback-only `SubscribeLocalEvents` / `GetLocalState` RPCs are not
/// served to remote peers and return UNIMPLEMENTED.
class ConnectibleServer extends pb.ConnectibleServiceBase {
  ConnectibleServer(this._delegate, this._pairing);

  final ServerDelegate _delegate;
  final PairingManager _pairing;

  /// Requester identities captured at Pair time so ConfirmPin (which only
  /// carries a device_id) can persist the full device on success.
  final Map<String, pb.Identity> _pendingIdentities = {};

  Server? _server;

  Stream<PairingRequestedEvent> get pairingEvents => _pairing.events;

  /// Binds the TLS 1.3 gRPC server on [port] (defaults to [kServerPort]).
  /// Safe to call once; a prior server is shut down first. Returns the
  /// bound port (useful when [port] is 0 for an ephemeral test port).
  Future<int> start(ServerIdentity identity, {int port = kServerPort}) async {
    await stop();
    final server = Server.create(services: [this]);
    // Phase G, T-G6 investigated requesting a client certificate here
    // (`requestClientCertificate: true`), mirroring the daemon's
    // `AcceptAnyClientCert`. Reverted: unlike rustls, `dart:io`'s
    // `SecureServerSocket` always chain-verifies whatever client
    // certificate is presented and rejects the handshake outright if it
    // doesn't validate -- there is no "accept any, decide later" escape
    // hatch, so setting this makes every client-cert-bearing connection
    // (i.e. any connect from this codebase's own `GrpcService`, which
    // always presents one) fail with `CERTIFICATE_VERIFY_FAILED: self
    // signed certificate`, confirmed with a standalone `SecureServerSocket`
    // reproduction. Mobile's responder-side pairing gate instead checks
    // claimed device_id against the paired store only (see
    // `PairingModel.onInboundSyncStream`) -- no TLS-layer identity
    // binding on this side, since the platform does not offer one.
    await server.serve(
      port: port,
      security: Tls13OnlyServerCredentials(
        certificate: identity.certBytes,
        privateKey: identity.keyBytes,
      ),
    );
    _server = server;
    final bound = server.port ?? port;
    debugPrint('connectible server listening on :$bound');
    return bound;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.shutdown();
    }
  }

  // --- RPC handlers (remote peer facing) -------------------------------

  @override
  Future<pb.PairResponse> pair(ServiceCall call, pb.PairRequest request) async {
    final requester = request.requester;
    if (requester.deviceId.isEmpty) {
      return pb.PairResponse(
        accepted: false,
        error: pb.Error(
          code: pb.ErrorCode.ERROR_CODE_PAIRING_REJECTED,
          message: 'missing requester identity',
        ),
      );
    }
    _pendingIdentities[requester.deviceId] = requester;
    try {
      final expiresAtMs = _pairing.createPending(
        requester.deviceId,
        requester.deviceName.isEmpty ? 'Unknown device' : requester.deviceName,
      );
      return pb.PairResponse(
        accepted: true,
        pinExpiresAtMs: Int64(expiresAtMs),
      );
    } on RateLimitedException catch (e) {
      // T-403: reported in the response body, not a gRPC-level error,
      // matching the daemon's convention for a normal/expected outcome
      // the caller should display rather than treat as a transport
      // failure.
      return pb.PairResponse(
        accepted: false,
        error: pb.Error(
          code: pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
          message: e.message,
        ),
      );
    }
  }

  @override
  Future<pb.ConfirmPinResponse> confirmPin(
      ServiceCall call, pb.ConfirmPinRequest request) async {
    final result = _pairing.confirm(request.deviceId, request.pinCode);
    switch (result) {
      case PinResult.ok:
        final identity = _pendingIdentities.remove(request.deviceId);
        if (identity != null) {
          _delegate.onPeerPaired(identity);
        }
        return pb.ConfirmPinResponse(verified: true);
      case PinResult.invalid:
        return pb.ConfirmPinResponse(
          verified: false,
          error: pb.Error(
            code: pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
            message: 'incorrect PIN',
          ),
        );
      case PinResult.timeout:
        _pendingIdentities.remove(request.deviceId);
        return pb.ConfirmPinResponse(
          verified: false,
          error: pb.Error(
            code: pb.ErrorCode.ERROR_CODE_PAIRING_TIMEOUT,
            message: 'pairing timed out',
          ),
        );
      case PinResult.noPending:
        return pb.ConfirmPinResponse(
          verified: false,
          error: pb.Error(
            code: pb.ErrorCode.ERROR_CODE_PAIRING_REJECTED,
            message: 'no pending pairing',
          ),
        );
    }
  }

  @override
  Future<pb.PongRequest> ping(ServiceCall call, pb.PingRequest request) async {
    return pb.PongRequest(
      sentAtMs: request.sentAtMs,
      repliedAtMs: Int64(DateTime.now().millisecondsSinceEpoch),
    );
  }

  @override
  Future<pb.ListDevicesResponse> listDevices(
      ServiceCall call, pb.ListDevicesRequest request) async {
    final devices = _delegate.knownDevices().map((d) => pb.DeviceInfo(
          identity: pb.Identity(
            deviceId: d.deviceId,
            deviceName: d.deviceName,
          ),
          online: d.online,
          pairedAtMs: Int64(d.pairedAtMs),
          lastSeenMs: Int64(d.lastSeenMs),
        ));
    return pb.ListDevicesResponse(devices: devices);
  }

  @override
  Stream<pb.SyncFrame> syncStream(
      ServiceCall call, Stream<pb.SyncFrame> request) {
    return _delegate.onInboundSyncStream(request);
  }

  // --- loopback-only RPCs: never served to remote peers ----------------

  @override
  Stream<pb.LocalEvent> subscribeLocalEvents(
      ServiceCall call, pb.LocalEventsRequest request) {
    throw const GrpcError.unimplemented('SubscribeLocalEvents is loopback-only');
  }

  @override
  Future<pb.GetLocalStateResponse> getLocalState(
      ServiceCall call, pb.GetLocalStateRequest request) async {
    throw const GrpcError.unimplemented('GetLocalState is loopback-only');
  }

  @override
  Future<pb.DisconnectDeviceResponse> disconnectDevice(
      ServiceCall call, pb.DisconnectDeviceRequest request) async {
    throw const GrpcError.unimplemented('DisconnectDevice is loopback-only');
  }

  @override
  Future<pb.ForgetDeviceResponse> forgetDevice(
      ServiceCall call, pb.ForgetDeviceRequest request) async {
    throw const GrpcError.unimplemented('ForgetDevice is loopback-only');
  }

  @override
  Future<pb.SetRemoteInputEnabledResponse> setRemoteInputEnabled(
      ServiceCall call, pb.SetRemoteInputEnabledRequest request) async {
    throw const GrpcError.unimplemented('SetRemoteInputEnabled is loopback-only');
  }

  @override
  Future<pb.SetClipboardSyncEnabledResponse> setClipboardSyncEnabled(
      ServiceCall call, pb.SetClipboardSyncEnabledRequest request) async {
    throw const GrpcError.unimplemented('SetClipboardSyncEnabled is loopback-only');
  }

  @override
  Future<pb.GetPinnedFingerprintResponse> getPinnedFingerprint(
      ServiceCall call, pb.GetPinnedFingerprintRequest request) async {
    throw const GrpcError.unimplemented('GetPinnedFingerprint is loopback-only');
  }

  @override
  Future<pb.PreArmPairingCodeResponse> preArmPairingCode(
      ServiceCall call, pb.PreArmPairingCodeRequest request) async {
    // Loopback-only, same as the RPCs above -- and mobile additionally
    // has no pre-arm concept in `PairingManager` at all yet (it only
    // supports responder-side createPending/confirm keyed to an
    // already-known requester), so this would need real design work
    // beyond "just implement it" even if it were remote-facing. See the
    // desktop's own `pre_arm_pairing_code` for the daemon-side
    // reference implementation if mobile-generated QR pairing (scan a
    // code shown *on the phone*) is ever prioritized.
    throw const GrpcError.unimplemented(
        'PreArmPairingCode is loopback-only and not yet implemented on mobile');
  }

  @override
  Future<pb.RecordFingerprintResponse> recordFingerprint(
      ServiceCall call, pb.RecordFingerprintRequest request) async {
    throw const GrpcError.unimplemented('RecordFingerprint is loopback-only');
  }

  @override
  Future<pb.RunDiagnosticsResponse> runDiagnostics(
      ServiceCall call, pb.RunDiagnosticsRequest request) async {
    // The daemon serves this loopback-only diagnostics RPC; the mobile app
    // runs its own in-process Doctor (T-F9/F10) instead of exposing one.
    throw const GrpcError.unimplemented('RunDiagnostics is loopback-only');
  }

  // --- dedicated file upload (TASKS.md Phase A) ------------------------
  // The gRPC surface only marshals; the delegate (PairingModel) does the
  // paired-sender authorization and forwards to FileTransferModel, which
  // streams to disk with a folded SHA-256 (no whole-file buffering).

  @override
  Future<pb.PrepareUploadResponse> prepareUpload(
          ServiceCall call, pb.PrepareUploadRequest request) =>
      _delegate.prepareUpload(request);

  @override
  Future<pb.UploadFileResult> uploadFile(
          ServiceCall call, Stream<pb.UploadFilePart> request) =>
      _delegate.uploadFile(request);
}
