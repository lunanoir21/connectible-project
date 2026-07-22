import '../generated/connectible.pbgrpc.dart' as pb;

/// Narrow interface [ClipboardModel] and [FileTransferModel] depend on to
/// reach the active paired session, without either of them needing a
/// concrete dependency on [PairingModel] (which owns the connection
/// lifecycle). [PairingModel] implements this; the two feature models only
/// ever see this interface (T-204 -- constructor injection instead of a
/// shared god-object).
abstract class SyncConnection {
  /// True while a SyncStream session is active (either as requester, after
  /// a successful ConfirmPin, or as responder, once a peer opens the
  /// inbound stream).
  bool get connected;

  /// The paired peer's device id, when known -- used to derive a stable
  /// (peer, file) transfer id for resumable sends. Null if no peer has
  /// been established yet (e.g. this device is only acting as a
  /// responder and has not opened an outgoing session).
  String? get activePeerId;

  /// Pushes one frame onto the active session's outbound stream. A no-op
  /// if there is no active session.
  void sendFrame(pb.SyncFrame frame);

  /// The active peer's gRPC client, for the dedicated file-upload RPCs
  /// (PrepareUpload + UploadFile) -- bulk bytes go here, on their own
  /// RPC/stream, not multiplexed onto [sendFrame]'s SyncStream. Null when
  /// there is no outgoing session to a peer (so a send is a no-op).
  pb.ConnectibleClient? get uploadClient;

  /// This device's own identity, declared as the sender in
  /// PrepareUpload so the peer can authorize it against its paired set.
  pb.Identity get localIdentity;
}
