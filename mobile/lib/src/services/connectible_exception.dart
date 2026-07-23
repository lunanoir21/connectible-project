import '../generated/connectible.pb.dart' as pb;

/// Project-defined exception hierarchy (T-205) mirroring the proto's
/// `ErrorCode` enum 1:1, so callers can catch/match on a specific failure
/// kind (e.g. `on PairingTimeoutException`) instead of parsing a message
/// string or catching a flat `GrpcServiceException`.
///
/// `sealed` gives exhaustiveness checking on a `switch` over the
/// hierarchy; every subclass lives in this file.
sealed class ConnectibleException implements Exception {
  const ConnectibleException(this.message);

  /// Human-readable detail from the peer (or, for
  /// [UnspecifiedConnectibleException], from the underlying platform/
  /// transport failure that never carried a proto `ErrorCode` at all).
  final String message;

  /// The proto `ErrorCode` this exception corresponds to.
  pb.ErrorCode get code;

  /// Builds the subclass matching a proto `Error` message's `code`, so a
  /// call site can do `throw ConnectibleException.fromError(resp.error)`
  /// without a switch of its own.
  factory ConnectibleException.fromError(pb.Error error) =>
      ConnectibleException.forCode(error.code, error.message);

  /// Builds the subclass matching [code] directly, for call sites that
  /// have an `ErrorCode` and message but no full proto `Error`.
  factory ConnectibleException.forCode(pb.ErrorCode code, String message) {
    switch (code) {
      case pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED:
        return UnauthenticatedException(message);
      case pb.ErrorCode.ERROR_CODE_PAIRING_REJECTED:
        return PairingRejectedException(message);
      case pb.ErrorCode.ERROR_CODE_PAIRING_TIMEOUT:
        return PairingTimeoutException(message);
      case pb.ErrorCode.ERROR_CODE_DEVICE_NOT_FOUND:
        return DeviceNotFoundException(message);
      case pb.ErrorCode.ERROR_CODE_FILE_TRANSFER_FAILED:
        return FileTransferFailedException(message);
      case pb.ErrorCode.ERROR_CODE_CHECKSUM_MISMATCH:
        return ChecksumMismatchException(message);
      case pb.ErrorCode.ERROR_CODE_UNSUPPORTED_PLATFORM:
        return UnsupportedPlatformException(message);
      case pb.ErrorCode.ERROR_CODE_INTERNAL:
        return InternalException(message);
      case pb.ErrorCode.ERROR_CODE_PROTOCOL_VERSION_MISMATCH:
        return ProtocolVersionMismatchException(message);
      case pb.ErrorCode.ERROR_CODE_RATE_LIMITED:
        return RateLimitedException(message);
      case pb.ErrorCode.ERROR_CODE_FINGERPRINT_CHANGED:
        return FingerprintChangedException(message);
      case pb.ErrorCode.ERROR_CODE_UNSPECIFIED:
        return UnspecifiedConnectibleException(message);
      default:
        return UnspecifiedConnectibleException(message);
    }
  }

  @override
  String toString() => '$runtimeType: $message';
}

/// No specific `ErrorCode` applies -- either the peer genuinely sent
/// `ERROR_CODE_UNSPECIFIED`, or (more commonly) the failure never reached
/// the proto layer at all (DNS/socket/TLS failure, a decode error, etc.)
/// and is being wrapped here so callers only ever need to catch one
/// exception hierarchy.
class UnspecifiedConnectibleException extends ConnectibleException {
  const UnspecifiedConnectibleException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_UNSPECIFIED;
}

/// Mirrors `ERROR_CODE_UNAUTHENTICATED`: the peer rejected the call
/// because the session/credential presented was not valid (e.g. a wrong
/// PIN submitted to `ConfirmPin`).
class UnauthenticatedException extends ConnectibleException {
  const UnauthenticatedException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED;
}

/// Mirrors `ERROR_CODE_PAIRING_REJECTED`: the responder declined the
/// pairing request outright (not a timeout, not a wrong PIN).
class PairingRejectedException extends ConnectibleException {
  const PairingRejectedException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_PAIRING_REJECTED;
}

/// Mirrors `ERROR_CODE_PAIRING_TIMEOUT`: the PIN window (or attempt
/// budget) expired before pairing completed.
class PairingTimeoutException extends ConnectibleException {
  const PairingTimeoutException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_PAIRING_TIMEOUT;
}

/// Mirrors `ERROR_CODE_DEVICE_NOT_FOUND`: the target device id is not
/// known to the peer (e.g. it was unpaired/forgotten).
class DeviceNotFoundException extends ConnectibleException {
  const DeviceNotFoundException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_DEVICE_NOT_FOUND;
}

/// Mirrors `ERROR_CODE_FILE_TRANSFER_FAILED`: a transfer could not
/// complete for a reason other than a checksum mismatch (disk I/O,
/// unexpected stream termination, etc.).
class FileTransferFailedException extends ConnectibleException {
  const FileTransferFailedException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_FILE_TRANSFER_FAILED;
}

/// Mirrors `ERROR_CODE_CHECKSUM_MISMATCH`: a chunk or whole-file hash
/// did not match what the sender declared.
class ChecksumMismatchException extends ConnectibleException {
  const ChecksumMismatchException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_CHECKSUM_MISMATCH;
}

/// Mirrors `ERROR_CODE_UNSUPPORTED_PLATFORM`: the requested capability
/// (e.g. remote input) is not available on the peer's platform.
class UnsupportedPlatformException extends ConnectibleException {
  const UnsupportedPlatformException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_UNSUPPORTED_PLATFORM;
}

/// Mirrors `ERROR_CODE_INTERNAL`: an unexpected error on the peer's side
/// not otherwise classified.
class InternalException extends ConnectibleException {
  const InternalException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_INTERNAL;
}

/// Mirrors `ERROR_CODE_PROTOCOL_VERSION_MISMATCH`: the peer speaks an
/// incompatible protocol version.
class ProtocolVersionMismatchException extends ConnectibleException {
  const ProtocolVersionMismatchException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_PROTOCOL_VERSION_MISMATCH;
}

/// Mirrors `ERROR_CODE_RATE_LIMITED`: the caller is being throttled
/// (e.g. repeated `Pair`/`ConfirmPin` attempts).
class RateLimitedException extends ConnectibleException {
  const RateLimitedException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_RATE_LIMITED;
}

/// Mirrors `ERROR_CODE_FINGERPRINT_CHANGED` (T-X33): the peer's pinned
/// TLS certificate no longer matches what it presented -- a MITM-or-
/// reinstall signal. Only a forget+re-pair can resolve it, so this is
/// its own type rather than falling into [UnspecifiedConnectibleException]
/// (previously the case, since `forCode`'s switch had no arm for this
/// code): callers can match on it to show the same dedicated,
/// actionable string [PairingModel] already shows for the client-side
/// TOFU-mismatch case it detects locally (`home.fingerprintChanged`).
class FingerprintChangedException extends ConnectibleException {
  const FingerprintChangedException(super.message);
  @override
  pb.ErrorCode get code => pb.ErrorCode.ERROR_CODE_FINGERPRINT_CHANGED;
}
