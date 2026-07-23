library;

import 'dart:typed_data';

/// UI-facing models, kept independent of the generated proto types so
/// the service layer can convert once at the edge and the widgets never
/// touch wire encodings.

class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.online,
    required this.pairedAtMs,
    required this.lastSeenMs,
    this.platform = '',
    this.certFingerprint = '',
  });

  final String deviceId;
  final String deviceName;
  final bool online;
  final int pairedAtMs;
  final int lastSeenMs;

  /// The paired peer's platform enum name (e.g. "PLATFORM_ANDROID",
  /// "PLATFORM_LINUX_X11"), carried from its Identity so the UI can show
  /// a platform icon. Empty when unknown (e.g. a legacy persisted entry).
  final String platform;

  /// TOFU (Phase C / T-C4): the peer server cert fingerprint pinned at
  /// first pairing (lowercase hex SHA-256 of the cert DER). Empty when not
  /// yet pinned (a legacy persisted entry, backfilled on next connect).
  final String certFingerprint;
}

class NearbyDevice {
  const NearbyDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.host,
    required this.port,
  });

  final String deviceId;
  final String deviceName;
  final String platform; // e.g. "PLATFORM_LINUX_X11"
  final String host; // resolved IP address
  final int port;
}

class ClipboardEntry {
  const ClipboardEntry({
    required this.content,
    required this.capturedAtMs,
    required this.source,
    this.mimeType = 'text/plain',
    this.imageBytes,
    this.oversized = false,
    this.byteSize = 0,
  });

  /// Decoded text; empty for image entries and for oversized entries
  /// (Phase L, T-L8 -- an oversized entry's bytes are never held in
  /// memory, only its metadata).
  final String content;
  final int capturedAtMs;
  final String source; // "local" or a peer device name/id

  /// "text/plain" or "image/png" (Phase L, T-L7). Defaults to
  /// "text/plain" so existing text-only callers are unaffected.
  final String mimeType;

  /// Raw image bytes when [mimeType] is an image type; null otherwise
  /// (including for oversized entries).
  final Uint8List? imageBytes;

  /// True when the original content exceeded the sync size cap and was
  /// recorded for visibility only -- see daemon's `MAX_CLIPBOARD_BYTES`.
  final bool oversized;

  /// Actual size in bytes; only meaningful to display when [oversized]
  /// is true.
  final int byteSize;

  bool get isImage => mimeType.startsWith('image/');
}

enum TransferDirection { incoming, outgoing }

class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.direction,
    this.completed = false,
    this.failed = false,
    this.canceled = false,
    this.finishedAtMs,
    this.peerDeviceId,
  });

  final String transferId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final TransferDirection direction;
  final bool completed;
  final bool failed;
  final bool canceled;

  // T-X24 display aids (mobile half of desktop's T-X16), not part of the
  // live upload/send path itself. `finishedAtMs` is stamped client-side
  // the moment a live transfer reaches a terminal state, so the merged
  // history list can sort chronologically; `peerDeviceId` is only present
  // on rows built from persisted history (a live in-session row doesn't
  // carry a peer id) -- see `transfers_screen.dart`.
  final int? finishedAtMs;
  final String? peerDeviceId;

  bool get active => !completed && !failed;

  double get fraction =>
      totalBytes <= 0 ? 0 : (bytesTransferred / totalBytes).clamp(0, 1);
}

/// One persisted transfer_history entry (Phase J): mobile has no
/// separate daemon process, so unlike desktop this is kept entirely by
/// [FileTransferModel] itself, in `shared_preferences`, mirroring
/// `DeviceListModel`'s paired-device roster persistence pattern.
class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.transferId,
    required this.peerDeviceId,
    required this.fileName,
    required this.totalBytes,
    required this.direction,
    required this.status,
    required this.startedAtMs,
    required this.finishedAtMs,
    this.localPath = '',
  });

  final String transferId;
  final String peerDeviceId;
  final String fileName;
  final int totalBytes;
  final TransferDirection direction;
  /// "completed" | "failed" | "canceled".
  final String status;
  final int startedAtMs;
  final int finishedAtMs;

  /// On-disk path of a completed *incoming* transfer's final file inside
  /// the app-private `received/` directory (T-X5), so "Save to..." still
  /// works after an app restart. Empty for outgoing transfers, for
  /// non-completed ones, and for entries persisted before this field
  /// existed (the JSON key is optional/backward-compatible).
  final String localPath;
}

class PairingPrompt {
  const PairingPrompt({
    required this.requesterDeviceId,
    required this.requesterDeviceName,
    required this.pinCode,
    required this.pinExpiresAtMs,
  });

  final String requesterDeviceId;
  final String requesterDeviceName;
  final String pinCode;
  final int pinExpiresAtMs;
}
