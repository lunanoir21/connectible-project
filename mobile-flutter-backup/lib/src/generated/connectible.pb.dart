//
//  Generated code. Do not modify.
//  source: connectible.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'connectible.pbenum.dart';

export 'connectible.pbenum.dart';

/// Sent immediately after TLS handshake completes, in both directions,
/// before any other message. Establishes who the peer is and what
/// protocol/capabilities it speaks. Also re-sent (without device_id
/// changing) on every reconnect so either side can detect a stale
/// cached name/type and refresh its UI.
class Identity extends $pb.GeneratedMessage {
  factory Identity({
    $core.String? deviceId,
    $core.String? deviceName,
    Platform? platform,
    DeviceType? deviceType,
    $core.int? protocolVersion,
    $core.String? appVersion,
    $core.Iterable<$core.String>? capabilities,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (deviceType != null) {
      $result.deviceType = deviceType;
    }
    if (protocolVersion != null) {
      $result.protocolVersion = protocolVersion;
    }
    if (appVersion != null) {
      $result.appVersion = appVersion;
    }
    if (capabilities != null) {
      $result.capabilities.addAll(capabilities);
    }
    return $result;
  }
  Identity._() : super();
  factory Identity.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Identity.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Identity', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..e<Platform>(3, _omitFieldNames ? '' : 'platform', $pb.PbFieldType.OE, defaultOrMaker: Platform.PLATFORM_UNSPECIFIED, valueOf: Platform.valueOf, enumValues: Platform.values)
    ..e<DeviceType>(4, _omitFieldNames ? '' : 'deviceType', $pb.PbFieldType.OE, defaultOrMaker: DeviceType.DEVICE_TYPE_UNSPECIFIED, valueOf: DeviceType.valueOf, enumValues: DeviceType.values)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'protocolVersion', $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'appVersion')
    ..pPS(7, _omitFieldNames ? '' : 'capabilities')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Identity clone() => Identity()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Identity copyWith(void Function(Identity) updates) => super.copyWith((message) => updates(message as Identity)) as Identity;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Identity create() => Identity._();
  Identity createEmptyInstance() => create();
  static $pb.PbList<Identity> createRepeated() => $pb.PbList<Identity>();
  @$core.pragma('dart2js:noInline')
  static Identity getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Identity>(create);
  static Identity? _defaultInstance;

  /// Stable, randomly generated UUIDv4 assigned on first run and
  /// persisted to disk. This is the primary key used in the SQLite
  /// `devices` table -- never derive it from hostname or IP, both of
  /// which can change.
  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  /// User-facing device name (e.g. "Anil's Laptop"). May be edited by
  /// the user post-pairing; changes are broadcast via a fresh Identity
  /// message on the next handshake.
  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => clearField(2);

  @$pb.TagNumber(3)
  Platform get platform => $_getN(2);
  @$pb.TagNumber(3)
  set platform(Platform v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => clearField(3);

  @$pb.TagNumber(4)
  DeviceType get deviceType => $_getN(3);
  @$pb.TagNumber(4)
  set deviceType(DeviceType v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceType() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceType() => clearField(4);

  /// Monotonically increasing protocol version this build speaks.
  /// Peers negotiate the lower of the two versions. A mismatch that
  /// cannot be bridged results in ERROR_CODE_PROTOCOL_VERSION_MISMATCH.
  @$pb.TagNumber(5)
  $core.int get protocolVersion => $_getIZ(4);
  @$pb.TagNumber(5)
  set protocolVersion($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasProtocolVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearProtocolVersion() => clearField(5);

  /// Application (daemon/app) semantic version string, informational
  /// only, shown in UI for debugging ("connected to v0.3.1").
  @$pb.TagNumber(6)
  $core.String get appVersion => $_getSZ(5);
  @$pb.TagNumber(6)
  set appVersion($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAppVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearAppVersion() => clearField(6);

  /// Capability flags so peers can skip probing for features that will
  /// never be supported (e.g. a headless daemon build with no input
  /// injection backend compiled in).
  @$pb.TagNumber(7)
  $core.List<$core.String> get capabilities => $_getList(6);
}

/// Pushed whenever the local clipboard changes and the feature is
/// enabled for the target device. The receiving side applies it to its
/// own clipboard and MUST suppress the resulting local change-detection
/// event to avoid an infinite echo loop (track last-applied hash).
class ClipboardData extends $pb.GeneratedMessage {
  factory ClipboardData({
    $core.String? mimeType,
    $core.List<$core.int>? content,
    $fixnum.Int64? capturedAtMs,
    $core.String? contentHash,
  }) {
    final $result = create();
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (content != null) {
      $result.content = content;
    }
    if (capturedAtMs != null) {
      $result.capturedAtMs = capturedAtMs;
    }
    if (contentHash != null) {
      $result.contentHash = contentHash;
    }
    return $result;
  }
  ClipboardData._() : super();
  factory ClipboardData.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClipboardData.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClipboardData', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mimeType')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'capturedAtMs')
    ..aOS(4, _omitFieldNames ? '' : 'contentHash')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClipboardData clone() => ClipboardData()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClipboardData copyWith(void Function(ClipboardData) updates) => super.copyWith((message) => updates(message as ClipboardData)) as ClipboardData;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClipboardData create() => ClipboardData._();
  ClipboardData createEmptyInstance() => create();
  static $pb.PbList<ClipboardData> createRepeated() => $pb.PbList<ClipboardData>();
  @$core.pragma('dart2js:noInline')
  static ClipboardData getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClipboardData>(create);
  static ClipboardData? _defaultInstance;

  /// MIME type of `content`, e.g. "text/plain", "image/png". MVP only
  /// guarantees text/plain; other types are best-effort.
  @$pb.TagNumber(1)
  $core.String get mimeType => $_getSZ(0);
  @$pb.TagNumber(1)
  set mimeType($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMimeType() => $_has(0);
  @$pb.TagNumber(1)
  void clearMimeType() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get content => $_getN(1);
  @$pb.TagNumber(2)
  set content($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => clearField(2);

  /// Unix epoch milliseconds when the clipboard change was captured on
  /// the sending side. Used for last-writer-wins conflict resolution
  /// and to detect clock skew (see Error handling / edge cases in
  /// PLAN.md); a receiver should log a warning, not fail, on skew.
  @$pb.TagNumber(3)
  $fixnum.Int64 get capturedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set capturedAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCapturedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapturedAtMs() => clearField(3);

  /// SHA-256 hex digest of `content`, used for echo-suppression and to
  /// let large clipboard payloads be deduplicated without re-hashing.
  @$pb.TagNumber(4)
  $core.String get contentHash => $_getSZ(3);
  @$pb.TagNumber(4)
  set contentHash($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContentHash() => $_has(3);
  @$pb.TagNumber(4)
  void clearContentHash() => clearField(4);
}

/// One remote-desktop input event. Sent at high frequency during an
/// active remote-control session (mouse move can be dozens of
/// messages/second), so keep this message as small as possible -- that
/// is why coordinates are normalized floats rather than event-specific
/// sub-messages with padding.
class RemoteInputEvent extends $pb.GeneratedMessage {
  factory RemoteInputEvent({
    InputEventType? type,
    $core.double? x,
    $core.double? y,
    MouseButton? button,
    $core.bool? pressed,
    $core.double? scrollDeltaX,
    $core.double? scrollDeltaY,
    $core.int? keyCode,
    $core.bool? keyPressed,
    $core.int? modifiers,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (x != null) {
      $result.x = x;
    }
    if (y != null) {
      $result.y = y;
    }
    if (button != null) {
      $result.button = button;
    }
    if (pressed != null) {
      $result.pressed = pressed;
    }
    if (scrollDeltaX != null) {
      $result.scrollDeltaX = scrollDeltaX;
    }
    if (scrollDeltaY != null) {
      $result.scrollDeltaY = scrollDeltaY;
    }
    if (keyCode != null) {
      $result.keyCode = keyCode;
    }
    if (keyPressed != null) {
      $result.keyPressed = keyPressed;
    }
    if (modifiers != null) {
      $result.modifiers = modifiers;
    }
    return $result;
  }
  RemoteInputEvent._() : super();
  factory RemoteInputEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RemoteInputEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RemoteInputEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..e<InputEventType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: InputEventType.INPUT_EVENT_TYPE_UNSPECIFIED, valueOf: InputEventType.valueOf, enumValues: InputEventType.values)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'x', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'y', $pb.PbFieldType.OF)
    ..e<MouseButton>(4, _omitFieldNames ? '' : 'button', $pb.PbFieldType.OE, defaultOrMaker: MouseButton.MOUSE_BUTTON_UNSPECIFIED, valueOf: MouseButton.valueOf, enumValues: MouseButton.values)
    ..aOB(5, _omitFieldNames ? '' : 'pressed')
    ..a<$core.double>(6, _omitFieldNames ? '' : 'scrollDeltaX', $pb.PbFieldType.OF)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'scrollDeltaY', $pb.PbFieldType.OF)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'keyCode', $pb.PbFieldType.OU3)
    ..aOB(9, _omitFieldNames ? '' : 'keyPressed')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'modifiers', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RemoteInputEvent clone() => RemoteInputEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RemoteInputEvent copyWith(void Function(RemoteInputEvent) updates) => super.copyWith((message) => updates(message as RemoteInputEvent)) as RemoteInputEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoteInputEvent create() => RemoteInputEvent._();
  RemoteInputEvent createEmptyInstance() => create();
  static $pb.PbList<RemoteInputEvent> createRepeated() => $pb.PbList<RemoteInputEvent>();
  @$core.pragma('dart2js:noInline')
  static RemoteInputEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RemoteInputEvent>(create);
  static RemoteInputEvent? _defaultInstance;

  @$pb.TagNumber(1)
  InputEventType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(InputEventType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  /// Normalized [0.0, 1.0] pointer position relative to the target
  /// display's top-left corner. Normalized (not pixel) coordinates let
  /// the sender not need to know the receiver's screen resolution.
  /// Populated for MOUSE_MOVE.
  @$pb.TagNumber(2)
  $core.double get x => $_getN(1);
  @$pb.TagNumber(2)
  set x($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasX() => $_has(1);
  @$pb.TagNumber(2)
  void clearX() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get y => $_getN(2);
  @$pb.TagNumber(3)
  set y($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasY() => $_has(2);
  @$pb.TagNumber(3)
  void clearY() => clearField(3);

  /// Populated for MOUSE_BUTTON.
  @$pb.TagNumber(4)
  MouseButton get button => $_getN(3);
  @$pb.TagNumber(4)
  set button(MouseButton v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasButton() => $_has(3);
  @$pb.TagNumber(4)
  void clearButton() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get pressed => $_getBF(4);
  @$pb.TagNumber(5)
  set pressed($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPressed() => $_has(4);
  @$pb.TagNumber(5)
  void clearPressed() => clearField(5);

  /// Populated for MOUSE_SCROLL. Positive = scroll up/right.
  @$pb.TagNumber(6)
  $core.double get scrollDeltaX => $_getN(5);
  @$pb.TagNumber(6)
  set scrollDeltaX($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasScrollDeltaX() => $_has(5);
  @$pb.TagNumber(6)
  void clearScrollDeltaX() => clearField(6);

  @$pb.TagNumber(7)
  $core.double get scrollDeltaY => $_getN(6);
  @$pb.TagNumber(7)
  set scrollDeltaY($core.double v) { $_setFloat(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasScrollDeltaY() => $_has(6);
  @$pb.TagNumber(7)
  void clearScrollDeltaY() => clearField(7);

  /// Populated for KEY. Uses the X11 keysym value so the Linux backend
  /// (ydotool / wayland-client) needs no translation table; other
  /// platforms map to/from their native keycodes at the edge.
  @$pb.TagNumber(8)
  $core.int get keyCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set keyCode($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasKeyCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearKeyCode() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get keyPressed => $_getBF(8);
  @$pb.TagNumber(9)
  set keyPressed($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasKeyPressed() => $_has(8);
  @$pb.TagNumber(9)
  void clearKeyPressed() => clearField(9);

  /// Optional modifier mask, bit flags: 1=shift, 2=ctrl, 4=alt, 8=meta.
  @$pb.TagNumber(10)
  $core.int get modifiers => $_getIZ(9);
  @$pb.TagNumber(10)
  set modifiers($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasModifiers() => $_has(9);
  @$pb.TagNumber(10)
  void clearModifiers() => clearField(10);
}

/// Announces an incoming file before any FileChunk is sent, allowing
/// the receiver to pre-allocate disk space, show a progress UI, and
/// reject the transfer up front (e.g. insufficient disk space, user
/// declines) without wasting bandwidth on chunks.
class FileTransferStart extends $pb.GeneratedMessage {
  factory FileTransferStart({
    $core.String? transferId,
    $core.String? fileName,
    $fixnum.Int64? fileSizeBytes,
    $core.String? fileHash,
    $core.int? chunkSizeBytes,
    $fixnum.Int64? resumeOffsetBytes,
    $core.String? mimeType,
  }) {
    final $result = create();
    if (transferId != null) {
      $result.transferId = transferId;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (fileSizeBytes != null) {
      $result.fileSizeBytes = fileSizeBytes;
    }
    if (fileHash != null) {
      $result.fileHash = fileHash;
    }
    if (chunkSizeBytes != null) {
      $result.chunkSizeBytes = chunkSizeBytes;
    }
    if (resumeOffsetBytes != null) {
      $result.resumeOffsetBytes = resumeOffsetBytes;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    return $result;
  }
  FileTransferStart._() : super();
  factory FileTransferStart.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FileTransferStart.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileTransferStart', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'transferId')
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aInt64(3, _omitFieldNames ? '' : 'fileSizeBytes')
    ..aOS(4, _omitFieldNames ? '' : 'fileHash')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'chunkSizeBytes', $pb.PbFieldType.OU3)
    ..aInt64(6, _omitFieldNames ? '' : 'resumeOffsetBytes')
    ..aOS(7, _omitFieldNames ? '' : 'mimeType')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FileTransferStart clone() => FileTransferStart()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FileTransferStart copyWith(void Function(FileTransferStart) updates) => super.copyWith((message) => updates(message as FileTransferStart)) as FileTransferStart;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileTransferStart create() => FileTransferStart._();
  FileTransferStart createEmptyInstance() => create();
  static $pb.PbList<FileTransferStart> createRepeated() => $pb.PbList<FileTransferStart>();
  @$core.pragma('dart2js:noInline')
  static FileTransferStart getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileTransferStart>(create);
  static FileTransferStart? _defaultInstance;

  /// Randomly generated per-transfer identifier correlating this
  /// announcement with the FileChunk stream and any resume request.
  @$pb.TagNumber(1)
  $core.String get transferId => $_getSZ(0);
  @$pb.TagNumber(1)
  set transferId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransferId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get fileSizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set fileSizeBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFileSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearFileSizeBytes() => clearField(3);

  /// SHA-256 hex digest of the complete file, verified by the receiver
  /// after the last chunk to catch corruption (see PLAN.md edge cases).
  @$pb.TagNumber(4)
  $core.String get fileHash => $_getSZ(3);
  @$pb.TagNumber(4)
  set fileHash($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFileHash() => $_has(3);
  @$pb.TagNumber(4)
  void clearFileHash() => clearField(4);

  /// Fixed chunk size in bytes this sender will use, so the receiver
  /// can pre-size its write buffer. MVP default is 65536 (65 KB).
  @$pb.TagNumber(5)
  $core.int get chunkSizeBytes => $_getIZ(4);
  @$pb.TagNumber(5)
  set chunkSizeBytes($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasChunkSizeBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearChunkSizeBytes() => clearField(5);

  /// If set, the receiver should attempt to resume a previously
  /// interrupted transfer with this transfer_id starting at
  /// resume_offset_bytes instead of starting from zero (see
  /// FileChunk.offset_bytes and PLAN.md network-interruption handling).
  @$pb.TagNumber(6)
  $fixnum.Int64 get resumeOffsetBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set resumeOffsetBytes($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasResumeOffsetBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearResumeOffsetBytes() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get mimeType => $_getSZ(6);
  @$pb.TagNumber(7)
  set mimeType($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMimeType() => $_has(6);
  @$pb.TagNumber(7)
  void clearMimeType() => clearField(7);
}

/// A single resumable chunk of file data. Chunks may be re-sent after a
/// dropped connection; the receiver deduplicates using offset_bytes, so
/// a resend of an already-written offset is a safe no-op overwrite.
class FileChunk extends $pb.GeneratedMessage {
  factory FileChunk({
    $core.String? transferId,
    $fixnum.Int64? offsetBytes,
    $core.List<$core.int>? data,
    $core.bool? isLast,
    $core.int? chunkChecksum,
  }) {
    final $result = create();
    if (transferId != null) {
      $result.transferId = transferId;
    }
    if (offsetBytes != null) {
      $result.offsetBytes = offsetBytes;
    }
    if (data != null) {
      $result.data = data;
    }
    if (isLast != null) {
      $result.isLast = isLast;
    }
    if (chunkChecksum != null) {
      $result.chunkChecksum = chunkChecksum;
    }
    return $result;
  }
  FileChunk._() : super();
  factory FileChunk.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FileChunk.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileChunk', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'transferId')
    ..aInt64(2, _omitFieldNames ? '' : 'offsetBytes')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOB(4, _omitFieldNames ? '' : 'isLast')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'chunkChecksum', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FileChunk clone() => FileChunk()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FileChunk copyWith(void Function(FileChunk) updates) => super.copyWith((message) => updates(message as FileChunk)) as FileChunk;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileChunk create() => FileChunk._();
  FileChunk createEmptyInstance() => create();
  static $pb.PbList<FileChunk> createRepeated() => $pb.PbList<FileChunk>();
  @$core.pragma('dart2js:noInline')
  static FileChunk getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileChunk>(create);
  static FileChunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get transferId => $_getSZ(0);
  @$pb.TagNumber(1)
  set transferId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransferId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferId() => clearField(1);

  /// Byte offset of `data` within the complete file. Explicit (rather
  /// than an implicit running counter) so chunks can be resumed or
  /// retried out of strict order after a reconnect.
  @$pb.TagNumber(2)
  $fixnum.Int64 get offsetBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set offsetBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOffsetBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffsetBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get data => $_getN(2);
  @$pb.TagNumber(3)
  set data($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => clearField(3);

  /// True on the final chunk of the transfer; triggers hash
  /// verification against FileTransferStart.file_hash on the receiver.
  @$pb.TagNumber(4)
  $core.bool get isLast => $_getBF(3);
  @$pb.TagNumber(4)
  set isLast($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsLast() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsLast() => clearField(4);

  /// CRC32 of this individual chunk's `data`, cheap to compute and lets
  /// the receiver detect a corrupted chunk immediately and request a
  /// re-send of just that chunk instead of failing the whole transfer.
  @$pb.TagNumber(5)
  $core.int get chunkChecksum => $_getIZ(4);
  @$pb.TagNumber(5)
  set chunkChecksum($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasChunkChecksum() => $_has(4);
  @$pb.TagNumber(5)
  void clearChunkChecksum() => clearField(5);
}

/// Polled periodically (MVP: every 60s, or on significant change) and
/// pushed to paired devices that have subscribed to battery updates.
class BatteryStatus extends $pb.GeneratedMessage {
  factory BatteryStatus({
    $core.int? percentage,
    $core.bool? isCharging,
    $core.int? minutesRemaining,
    $fixnum.Int64? reportedAtMs,
  }) {
    final $result = create();
    if (percentage != null) {
      $result.percentage = percentage;
    }
    if (isCharging != null) {
      $result.isCharging = isCharging;
    }
    if (minutesRemaining != null) {
      $result.minutesRemaining = minutesRemaining;
    }
    if (reportedAtMs != null) {
      $result.reportedAtMs = reportedAtMs;
    }
    return $result;
  }
  BatteryStatus._() : super();
  factory BatteryStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BatteryStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BatteryStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'percentage', $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'isCharging')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'minutesRemaining', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'reportedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BatteryStatus clone() => BatteryStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BatteryStatus copyWith(void Function(BatteryStatus) updates) => super.copyWith((message) => updates(message as BatteryStatus)) as BatteryStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BatteryStatus create() => BatteryStatus._();
  BatteryStatus createEmptyInstance() => create();
  static $pb.PbList<BatteryStatus> createRepeated() => $pb.PbList<BatteryStatus>();
  @$core.pragma('dart2js:noInline')
  static BatteryStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BatteryStatus>(create);
  static BatteryStatus? _defaultInstance;

  /// 0-100.
  @$pb.TagNumber(1)
  $core.int get percentage => $_getIZ(0);
  @$pb.TagNumber(1)
  set percentage($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPercentage() => $_has(0);
  @$pb.TagNumber(1)
  void clearPercentage() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isCharging => $_getBF(1);
  @$pb.TagNumber(2)
  set isCharging($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsCharging() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsCharging() => clearField(2);

  /// -1 if unknown / not reported by the platform (e.g. desktop with no
  /// battery, or a VM). Consumers must treat negative as "no estimate".
  @$pb.TagNumber(3)
  $core.int get minutesRemaining => $_getIZ(2);
  @$pb.TagNumber(3)
  set minutesRemaining($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMinutesRemaining() => $_has(2);
  @$pb.TagNumber(3)
  void clearMinutesRemaining() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get reportedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set reportedAtMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasReportedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearReportedAtMs() => clearField(4);
}

/// Forwards a system notification from one device to another (e.g.
/// phone notification mirrored to desktop).
class NotificationData extends $pb.GeneratedMessage {
  factory NotificationData({
    $core.String? notificationId,
    $core.String? appName,
    $core.String? title,
    $core.String? body,
    $core.List<$core.int>? icon,
    $fixnum.Int64? postedAtMs,
    $core.bool? isDismissal,
  }) {
    final $result = create();
    if (notificationId != null) {
      $result.notificationId = notificationId;
    }
    if (appName != null) {
      $result.appName = appName;
    }
    if (title != null) {
      $result.title = title;
    }
    if (body != null) {
      $result.body = body;
    }
    if (icon != null) {
      $result.icon = icon;
    }
    if (postedAtMs != null) {
      $result.postedAtMs = postedAtMs;
    }
    if (isDismissal != null) {
      $result.isDismissal = isDismissal;
    }
    return $result;
  }
  NotificationData._() : super();
  factory NotificationData.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NotificationData.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NotificationData', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'notificationId')
    ..aOS(2, _omitFieldNames ? '' : 'appName')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'body')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'icon', $pb.PbFieldType.OY)
    ..aInt64(6, _omitFieldNames ? '' : 'postedAtMs')
    ..aOB(7, _omitFieldNames ? '' : 'isDismissal')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NotificationData clone() => NotificationData()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NotificationData copyWith(void Function(NotificationData) updates) => super.copyWith((message) => updates(message as NotificationData)) as NotificationData;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NotificationData create() => NotificationData._();
  NotificationData createEmptyInstance() => create();
  static $pb.PbList<NotificationData> createRepeated() => $pb.PbList<NotificationData>();
  @$core.pragma('dart2js:noInline')
  static NotificationData getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NotificationData>(create);
  static NotificationData? _defaultInstance;

  /// Identifier from the originating platform's notification system,
  /// used to correlate a later dismiss/update/action-invoked event.
  @$pb.TagNumber(1)
  $core.String get notificationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set notificationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNotificationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNotificationId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get appName => $_getSZ(1);
  @$pb.TagNumber(2)
  set appName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAppName() => $_has(1);
  @$pb.TagNumber(2)
  void clearAppName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get body => $_getSZ(3);
  @$pb.TagNumber(4)
  set body($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasBody() => $_has(3);
  @$pb.TagNumber(4)
  void clearBody() => clearField(4);

  /// Optional icon, small (<= 64KB recommended); omit for text-only
  /// notifications to save bandwidth.
  @$pb.TagNumber(5)
  $core.List<$core.int> get icon => $_getN(4);
  @$pb.TagNumber(5)
  set icon($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIcon() => $_has(4);
  @$pb.TagNumber(5)
  void clearIcon() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get postedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set postedAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPostedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearPostedAtMs() => clearField(6);

  /// If true, this message represents dismissal of a previously
  /// forwarded notification (title/body/icon are unset in that case).
  @$pb.TagNumber(7)
  $core.bool get isDismissal => $_getBF(6);
  @$pb.TagNumber(7)
  set isDismissal($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsDismissal() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsDismissal() => clearField(7);
}

/// Generic error envelope, sent either as a unary RPC's error detail or
/// as a message on the SyncStream when an in-stream operation
/// (clipboard push, file chunk, input event) fails asynchronously and
/// there is no synchronous RPC response to attach the error to.
class Error extends $pb.GeneratedMessage {
  factory Error({
    ErrorCode? code,
    $core.String? message,
    $core.Map<$core.String, $core.String>? details,
  }) {
    final $result = create();
    if (code != null) {
      $result.code = code;
    }
    if (message != null) {
      $result.message = message;
    }
    if (details != null) {
      $result.details.addAll(details);
    }
    return $result;
  }
  Error._() : super();
  factory Error.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Error.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Error', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..e<ErrorCode>(1, _omitFieldNames ? '' : 'code', $pb.PbFieldType.OE, defaultOrMaker: ErrorCode.ERROR_CODE_UNSPECIFIED, valueOf: ErrorCode.valueOf, enumValues: ErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'details', entryClassName: 'Error.DetailsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('connectible.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Error clone() => Error()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Error copyWith(void Function(Error) updates) => super.copyWith((message) => updates(message as Error)) as Error;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Error create() => Error._();
  Error createEmptyInstance() => create();
  static $pb.PbList<Error> createRepeated() => $pb.PbList<Error>();
  @$core.pragma('dart2js:noInline')
  static Error getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Error>(create);
  static Error? _defaultInstance;

  @$pb.TagNumber(1)
  ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(ErrorCode v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);

  /// Free-form key/value context for logs/debugging, e.g.
  /// {"transfer_id": "...", "expected_hash": "...", "actual_hash": "..."}.
  @$pb.TagNumber(3)
  $core.Map<$core.String, $core.String> get details => $_getMap(2);
}

/// Sent by the receiver back to the sender when a FileChunk fails its
/// CRC32 check, asking for that one chunk to be resent rather than
/// aborting or falling back to a full resume-from-offset. The sender
/// treats this exactly like a fresh FileChunk send at offset_bytes.
class FileChunkRequest extends $pb.GeneratedMessage {
  factory FileChunkRequest({
    $core.String? transferId,
    $fixnum.Int64? offsetBytes,
  }) {
    final $result = create();
    if (transferId != null) {
      $result.transferId = transferId;
    }
    if (offsetBytes != null) {
      $result.offsetBytes = offsetBytes;
    }
    return $result;
  }
  FileChunkRequest._() : super();
  factory FileChunkRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FileChunkRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileChunkRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'transferId')
    ..aInt64(2, _omitFieldNames ? '' : 'offsetBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FileChunkRequest clone() => FileChunkRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FileChunkRequest copyWith(void Function(FileChunkRequest) updates) => super.copyWith((message) => updates(message as FileChunkRequest)) as FileChunkRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileChunkRequest create() => FileChunkRequest._();
  FileChunkRequest createEmptyInstance() => create();
  static $pb.PbList<FileChunkRequest> createRepeated() => $pb.PbList<FileChunkRequest>();
  @$core.pragma('dart2js:noInline')
  static FileChunkRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileChunkRequest>(create);
  static FileChunkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get transferId => $_getSZ(0);
  @$pb.TagNumber(1)
  set transferId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransferId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offsetBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set offsetBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOffsetBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffsetBytes() => clearField(2);
}

/// One file's metadata, declared up front so the receiver can accept or
/// decline (disk space, receiving disabled, unpaired sender) and report
/// how many bytes it already has for a resumed transfer -- before any
/// bytes are sent.
class UploadFileMeta extends $pb.GeneratedMessage {
  factory UploadFileMeta({
    $core.String? fileId,
    $core.String? fileName,
    $fixnum.Int64? fileSizeBytes,
    $core.String? fileHash,
    $core.String? mimeType,
  }) {
    final $result = create();
    if (fileId != null) {
      $result.fileId = fileId;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (fileSizeBytes != null) {
      $result.fileSizeBytes = fileSizeBytes;
    }
    if (fileHash != null) {
      $result.fileHash = fileHash;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    return $result;
  }
  UploadFileMeta._() : super();
  factory UploadFileMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UploadFileMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UploadFileMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aInt64(3, _omitFieldNames ? '' : 'fileSizeBytes')
    ..aOS(4, _omitFieldNames ? '' : 'fileHash')
    ..aOS(5, _omitFieldNames ? '' : 'mimeType')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UploadFileMeta clone() => UploadFileMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UploadFileMeta copyWith(void Function(UploadFileMeta) updates) => super.copyWith((message) => updates(message as UploadFileMeta)) as UploadFileMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFileMeta create() => UploadFileMeta._();
  UploadFileMeta createEmptyInstance() => create();
  static $pb.PbList<UploadFileMeta> createRepeated() => $pb.PbList<UploadFileMeta>();
  @$core.pragma('dart2js:noInline')
  static UploadFileMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UploadFileMeta>(create);
  static UploadFileMeta? _defaultInstance;

  /// Stable per (peer, file) identifier -- the sender derives it
  /// deterministically (peer id + path + size + mtime) so a retry after a
  /// dropped connection reuses the id the receiver kept its partial file
  /// under, which is what makes resume reachable. Not a fresh random per
  /// attempt.
  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get fileSizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set fileSizeBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFileSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearFileSizeBytes() => clearField(3);

  /// SHA-256 hex digest of the complete file. The receiver verifies its
  /// own streaming digest against this after the last byte; empty means
  /// "skip verification" (best-effort senders only).
  @$pb.TagNumber(4)
  $core.String get fileHash => $_getSZ(3);
  @$pb.TagNumber(4)
  set fileHash($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFileHash() => $_has(3);
  @$pb.TagNumber(4)
  void clearFileHash() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get mimeType => $_getSZ(4);
  @$pb.TagNumber(5)
  set mimeType($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMimeType() => $_has(4);
  @$pb.TagNumber(5)
  void clearMimeType() => clearField(5);
}

/// Sent once to open a transfer session covering one or more files. The
/// receiver answers with an accept/resume decision per file.
class PrepareUploadRequest extends $pb.GeneratedMessage {
  factory PrepareUploadRequest({
    Identity? sender,
    $core.String? sessionId,
    $core.Iterable<UploadFileMeta>? files,
  }) {
    final $result = create();
    if (sender != null) {
      $result.sender = sender;
    }
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (files != null) {
      $result.files.addAll(files);
    }
    return $result;
  }
  PrepareUploadRequest._() : super();
  factory PrepareUploadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PrepareUploadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareUploadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOM<Identity>(1, _omitFieldNames ? '' : 'sender', subBuilder: Identity.create)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..pc<UploadFileMeta>(3, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: UploadFileMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PrepareUploadRequest clone() => PrepareUploadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PrepareUploadRequest copyWith(void Function(PrepareUploadRequest) updates) => super.copyWith((message) => updates(message as PrepareUploadRequest)) as PrepareUploadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareUploadRequest create() => PrepareUploadRequest._();
  PrepareUploadRequest createEmptyInstance() => create();
  static $pb.PbList<PrepareUploadRequest> createRepeated() => $pb.PbList<PrepareUploadRequest>();
  @$core.pragma('dart2js:noInline')
  static PrepareUploadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareUploadRequest>(create);
  static PrepareUploadRequest? _defaultInstance;

  /// Who is sending. The receiver authorizes this against its paired-set
  /// (an unpaired sender is rejected before any file bytes move).
  @$pb.TagNumber(1)
  Identity get sender => $_getN(0);
  @$pb.TagNumber(1)
  set sender(Identity v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSender() => $_has(0);
  @$pb.TagNumber(1)
  void clearSender() => clearField(1);
  @$pb.TagNumber(1)
  Identity ensureSender() => $_ensure(0);

  /// Groups the files of one logical transfer so the receiver can key
  /// per-file tokens and progress under a single session.
  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<UploadFileMeta> get files => $_getList(2);
}

/// The receiver's per-file decision.
class UploadFileOffer extends $pb.GeneratedMessage {
  factory UploadFileOffer({
    $core.String? fileId,
    $core.bool? accepted,
    $fixnum.Int64? resumeOffsetBytes,
    $core.String? token,
    $core.String? rejectReason,
  }) {
    final $result = create();
    if (fileId != null) {
      $result.fileId = fileId;
    }
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (resumeOffsetBytes != null) {
      $result.resumeOffsetBytes = resumeOffsetBytes;
    }
    if (token != null) {
      $result.token = token;
    }
    if (rejectReason != null) {
      $result.rejectReason = rejectReason;
    }
    return $result;
  }
  UploadFileOffer._() : super();
  factory UploadFileOffer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UploadFileOffer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UploadFileOffer', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..aInt64(3, _omitFieldNames ? '' : 'resumeOffsetBytes')
    ..aOS(4, _omitFieldNames ? '' : 'token')
    ..aOS(5, _omitFieldNames ? '' : 'rejectReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UploadFileOffer clone() => UploadFileOffer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UploadFileOffer copyWith(void Function(UploadFileOffer) updates) => super.copyWith((message) => updates(message as UploadFileOffer)) as UploadFileOffer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFileOffer create() => UploadFileOffer._();
  UploadFileOffer createEmptyInstance() => create();
  static $pb.PbList<UploadFileOffer> createRepeated() => $pb.PbList<UploadFileOffer>();
  @$core.pragma('dart2js:noInline')
  static UploadFileOffer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UploadFileOffer>(create);
  static UploadFileOffer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => clearField(1);

  /// False when the receiver declines (receiving disabled, no disk space,
  /// sender not paired). reject_reason carries a machine-readable ErrorCode
  /// name for the UI to localize; token/resume are unset.
  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => clearField(2);

  /// Bytes the receiver already holds for this file_id (its partial's
  /// length). The sender begins UploadFile at this offset instead of 0.
  @$pb.TagNumber(3)
  $fixnum.Int64 get resumeOffsetBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set resumeOffsetBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResumeOffsetBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeOffsetBytes() => clearField(3);

  /// Opaque capability the sender must echo in UploadFileHeader; ties an
  /// UploadFile stream to this accepted offer so a stream can't be
  /// spoofed onto a file the receiver never agreed to accept.
  @$pb.TagNumber(4)
  $core.String get token => $_getSZ(3);
  @$pb.TagNumber(4)
  set token($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearToken() => clearField(4);

  /// ErrorCode name when accepted = false (e.g. "UNAUTHENTICATED",
  /// "FILE_TRANSFER_FAILED"); empty when accepted.
  @$pb.TagNumber(5)
  $core.String get rejectReason => $_getSZ(4);
  @$pb.TagNumber(5)
  set rejectReason($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRejectReason() => $_has(4);
  @$pb.TagNumber(5)
  void clearRejectReason() => clearField(5);
}

class PrepareUploadResponse extends $pb.GeneratedMessage {
  factory PrepareUploadResponse({
    $core.String? sessionId,
    $core.Iterable<UploadFileOffer>? offers,
  }) {
    final $result = create();
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (offers != null) {
      $result.offers.addAll(offers);
    }
    return $result;
  }
  PrepareUploadResponse._() : super();
  factory PrepareUploadResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PrepareUploadResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PrepareUploadResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..pc<UploadFileOffer>(2, _omitFieldNames ? '' : 'offers', $pb.PbFieldType.PM, subBuilder: UploadFileOffer.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PrepareUploadResponse clone() => PrepareUploadResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PrepareUploadResponse copyWith(void Function(PrepareUploadResponse) updates) => super.copyWith((message) => updates(message as PrepareUploadResponse)) as PrepareUploadResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrepareUploadResponse create() => PrepareUploadResponse._();
  PrepareUploadResponse createEmptyInstance() => create();
  static $pb.PbList<PrepareUploadResponse> createRepeated() => $pb.PbList<PrepareUploadResponse>();
  @$core.pragma('dart2js:noInline')
  static PrepareUploadResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PrepareUploadResponse>(create);
  static PrepareUploadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<UploadFileOffer> get offers => $_getList(1);
}

/// First message of an UploadFile stream: identifies which accepted offer
/// this byte stream fulfills and where it begins.
class UploadFileHeader extends $pb.GeneratedMessage {
  factory UploadFileHeader({
    $core.String? sessionId,
    $core.String? fileId,
    $core.String? token,
    $fixnum.Int64? offsetBytes,
  }) {
    final $result = create();
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (fileId != null) {
      $result.fileId = fileId;
    }
    if (token != null) {
      $result.token = token;
    }
    if (offsetBytes != null) {
      $result.offsetBytes = offsetBytes;
    }
    return $result;
  }
  UploadFileHeader._() : super();
  factory UploadFileHeader.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UploadFileHeader.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UploadFileHeader', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOS(2, _omitFieldNames ? '' : 'fileId')
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aInt64(4, _omitFieldNames ? '' : 'offsetBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UploadFileHeader clone() => UploadFileHeader()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UploadFileHeader copyWith(void Function(UploadFileHeader) updates) => super.copyWith((message) => updates(message as UploadFileHeader)) as UploadFileHeader;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFileHeader create() => UploadFileHeader._();
  UploadFileHeader createEmptyInstance() => create();
  static $pb.PbList<UploadFileHeader> createRepeated() => $pb.PbList<UploadFileHeader>();
  @$core.pragma('dart2js:noInline')
  static UploadFileHeader getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UploadFileHeader>(create);
  static UploadFileHeader? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileId => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileId() => clearField(2);

  /// The token minted in the matching UploadFileOffer; the receiver
  /// rejects a stream whose token/session/file_id don't match a live,
  /// accepted offer.
  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(2);
  @$pb.TagNumber(3)
  set token($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearToken() => clearField(3);

  /// Byte offset this stream starts at -- equal to the offer's
  /// resume_offset_bytes for a resumed transfer, 0 for a fresh one.
  @$pb.TagNumber(4)
  $fixnum.Int64 get offsetBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set offsetBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOffsetBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearOffsetBytes() => clearField(4);
}

enum UploadFilePart_Part {
  header, 
  chunk, 
  notSet
}

/// One frame of an UploadFile client-stream: exactly the header (first
/// frame) or a raw byte chunk (every subsequent frame). The chunk size is
/// the sender's choice; the receiver just appends at the running offset,
/// so backpressure is whatever the stream's flow control allows.
class UploadFilePart extends $pb.GeneratedMessage {
  factory UploadFilePart({
    UploadFileHeader? header,
    $core.List<$core.int>? chunk,
  }) {
    final $result = create();
    if (header != null) {
      $result.header = header;
    }
    if (chunk != null) {
      $result.chunk = chunk;
    }
    return $result;
  }
  UploadFilePart._() : super();
  factory UploadFilePart.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UploadFilePart.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, UploadFilePart_Part> _UploadFilePart_PartByTag = {
    1 : UploadFilePart_Part.header,
    2 : UploadFilePart_Part.chunk,
    0 : UploadFilePart_Part.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UploadFilePart', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<UploadFileHeader>(1, _omitFieldNames ? '' : 'header', subBuilder: UploadFileHeader.create)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'chunk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UploadFilePart clone() => UploadFilePart()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UploadFilePart copyWith(void Function(UploadFilePart) updates) => super.copyWith((message) => updates(message as UploadFilePart)) as UploadFilePart;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFilePart create() => UploadFilePart._();
  UploadFilePart createEmptyInstance() => create();
  static $pb.PbList<UploadFilePart> createRepeated() => $pb.PbList<UploadFilePart>();
  @$core.pragma('dart2js:noInline')
  static UploadFilePart getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UploadFilePart>(create);
  static UploadFilePart? _defaultInstance;

  UploadFilePart_Part whichPart() => _UploadFilePart_PartByTag[$_whichOneof(0)]!;
  void clearPart() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  UploadFileHeader get header => $_getN(0);
  @$pb.TagNumber(1)
  set header(UploadFileHeader v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasHeader() => $_has(0);
  @$pb.TagNumber(1)
  void clearHeader() => clearField(1);
  @$pb.TagNumber(1)
  UploadFileHeader ensureHeader() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.int> get chunk => $_getN(1);
  @$pb.TagNumber(2)
  set chunk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChunk() => $_has(1);
  @$pb.TagNumber(2)
  void clearChunk() => clearField(2);
}

/// Returned once the UploadFile stream ends (or is aborted). completed +
/// hash_ok are only both true when every byte arrived and the streaming
/// SHA-256 matched UploadFileMeta.file_hash.
class UploadFileResult extends $pb.GeneratedMessage {
  factory UploadFileResult({
    $core.String? fileId,
    $core.bool? completed,
    $fixnum.Int64? bytesReceived,
    $core.bool? hashOk,
  }) {
    final $result = create();
    if (fileId != null) {
      $result.fileId = fileId;
    }
    if (completed != null) {
      $result.completed = completed;
    }
    if (bytesReceived != null) {
      $result.bytesReceived = bytesReceived;
    }
    if (hashOk != null) {
      $result.hashOk = hashOk;
    }
    return $result;
  }
  UploadFileResult._() : super();
  factory UploadFileResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UploadFileResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UploadFileResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOB(2, _omitFieldNames ? '' : 'completed')
    ..aInt64(3, _omitFieldNames ? '' : 'bytesReceived')
    ..aOB(4, _omitFieldNames ? '' : 'hashOk')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UploadFileResult clone() => UploadFileResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UploadFileResult copyWith(void Function(UploadFileResult) updates) => super.copyWith((message) => updates(message as UploadFileResult)) as UploadFileResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadFileResult create() => UploadFileResult._();
  UploadFileResult createEmptyInstance() => create();
  static $pb.PbList<UploadFileResult> createRepeated() => $pb.PbList<UploadFileResult>();
  @$core.pragma('dart2js:noInline')
  static UploadFileResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UploadFileResult>(create);
  static UploadFileResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get completed => $_getBF(1);
  @$pb.TagNumber(2)
  set completed($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCompleted() => $_has(1);
  @$pb.TagNumber(2)
  void clearCompleted() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesReceived => $_getI64(2);
  @$pb.TagNumber(3)
  set bytesReceived($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBytesReceived() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytesReceived() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get hashOk => $_getBF(3);
  @$pb.TagNumber(4)
  set hashOk($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHashOk() => $_has(3);
  @$pb.TagNumber(4)
  void clearHashOk() => clearField(4);
}

class PairRequest extends $pb.GeneratedMessage {
  factory PairRequest({
    Identity? requester,
  }) {
    final $result = create();
    if (requester != null) {
      $result.requester = requester;
    }
    return $result;
  }
  PairRequest._() : super();
  factory PairRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PairRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PairRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOM<Identity>(1, _omitFieldNames ? '' : 'requester', subBuilder: Identity.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PairRequest clone() => PairRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PairRequest copyWith(void Function(PairRequest) updates) => super.copyWith((message) => updates(message as PairRequest)) as PairRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairRequest create() => PairRequest._();
  PairRequest createEmptyInstance() => create();
  static $pb.PbList<PairRequest> createRepeated() => $pb.PbList<PairRequest>();
  @$core.pragma('dart2js:noInline')
  static PairRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PairRequest>(create);
  static PairRequest? _defaultInstance;

  /// Identity of the device requesting pairing. The daemon receiving
  /// this call shows the 6-digit PIN dialog to its local user.
  @$pb.TagNumber(1)
  Identity get requester => $_getN(0);
  @$pb.TagNumber(1)
  set requester(Identity v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequester() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequester() => clearField(1);
  @$pb.TagNumber(1)
  Identity ensureRequester() => $_ensure(0);
}

class PairResponse extends $pb.GeneratedMessage {
  factory PairResponse({
    $core.bool? accepted,
    $fixnum.Int64? pinExpiresAtMs,
    Error? error,
  }) {
    final $result = create();
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (pinExpiresAtMs != null) {
      $result.pinExpiresAtMs = pinExpiresAtMs;
    }
    if (error != null) {
      $result.error = error;
    }
    return $result;
  }
  PairResponse._() : super();
  factory PairResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PairResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PairResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aInt64(2, _omitFieldNames ? '' : 'pinExpiresAtMs')
    ..aOM<Error>(3, _omitFieldNames ? '' : 'error', subBuilder: Error.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PairResponse clone() => PairResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PairResponse copyWith(void Function(PairResponse) updates) => super.copyWith((message) => updates(message as PairResponse)) as PairResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairResponse create() => PairResponse._();
  PairResponse createEmptyInstance() => create();
  static $pb.PbList<PairResponse> createRepeated() => $pb.PbList<PairResponse>();
  @$core.pragma('dart2js:noInline')
  static PairResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PairResponse>(create);
  static PairResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => clearField(1);

  /// 6-digit numeric code, valid for 30 seconds (see PLAN.md pairing
  /// sequence). Only populated when accepted = true and PIN entry is
  /// the next step (the responder generates and displays this code
  /// locally; it is also echoed here for logging/debug builds only --
  /// production UI should not rely on reading it back over the wire on
  /// the requester side).
  @$pb.TagNumber(2)
  $fixnum.Int64 get pinExpiresAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set pinExpiresAtMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPinExpiresAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearPinExpiresAtMs() => clearField(2);

  @$pb.TagNumber(3)
  Error get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(Error v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => clearField(3);
  @$pb.TagNumber(3)
  Error ensureError() => $_ensure(2);
}

class ConfirmPinRequest extends $pb.GeneratedMessage {
  factory ConfirmPinRequest({
    $core.String? deviceId,
    $core.String? pinCode,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (pinCode != null) {
      $result.pinCode = pinCode;
    }
    return $result;
  }
  ConfirmPinRequest._() : super();
  factory ConfirmPinRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ConfirmPinRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ConfirmPinRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'pinCode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ConfirmPinRequest clone() => ConfirmPinRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ConfirmPinRequest copyWith(void Function(ConfirmPinRequest) updates) => super.copyWith((message) => updates(message as ConfirmPinRequest)) as ConfirmPinRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmPinRequest create() => ConfirmPinRequest._();
  ConfirmPinRequest createEmptyInstance() => create();
  static $pb.PbList<ConfirmPinRequest> createRepeated() => $pb.PbList<ConfirmPinRequest>();
  @$core.pragma('dart2js:noInline')
  static ConfirmPinRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConfirmPinRequest>(create);
  static ConfirmPinRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get pinCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set pinCode($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPinCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearPinCode() => clearField(2);
}

class ConfirmPinResponse extends $pb.GeneratedMessage {
  factory ConfirmPinResponse({
    $core.bool? verified,
    Error? error,
  }) {
    final $result = create();
    if (verified != null) {
      $result.verified = verified;
    }
    if (error != null) {
      $result.error = error;
    }
    return $result;
  }
  ConfirmPinResponse._() : super();
  factory ConfirmPinResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ConfirmPinResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ConfirmPinResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'verified')
    ..aOM<Error>(2, _omitFieldNames ? '' : 'error', subBuilder: Error.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ConfirmPinResponse clone() => ConfirmPinResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ConfirmPinResponse copyWith(void Function(ConfirmPinResponse) updates) => super.copyWith((message) => updates(message as ConfirmPinResponse)) as ConfirmPinResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmPinResponse create() => ConfirmPinResponse._();
  ConfirmPinResponse createEmptyInstance() => create();
  static $pb.PbList<ConfirmPinResponse> createRepeated() => $pb.PbList<ConfirmPinResponse>();
  @$core.pragma('dart2js:noInline')
  static ConfirmPinResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConfirmPinResponse>(create);
  static ConfirmPinResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get verified => $_getBF(0);
  @$pb.TagNumber(1)
  set verified($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVerified() => $_has(0);
  @$pb.TagNumber(1)
  void clearVerified() => clearField(1);

  @$pb.TagNumber(2)
  Error get error => $_getN(1);
  @$pb.TagNumber(2)
  set error(Error v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => clearField(2);
  @$pb.TagNumber(2)
  Error ensureError() => $_ensure(1);
}

class ListDevicesRequest extends $pb.GeneratedMessage {
  factory ListDevicesRequest({
    $core.bool? onlineOnly,
  }) {
    final $result = create();
    if (onlineOnly != null) {
      $result.onlineOnly = onlineOnly;
    }
    return $result;
  }
  ListDevicesRequest._() : super();
  factory ListDevicesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ListDevicesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ListDevicesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'onlineOnly')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ListDevicesRequest clone() => ListDevicesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ListDevicesRequest copyWith(void Function(ListDevicesRequest) updates) => super.copyWith((message) => updates(message as ListDevicesRequest)) as ListDevicesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListDevicesRequest create() => ListDevicesRequest._();
  ListDevicesRequest createEmptyInstance() => create();
  static $pb.PbList<ListDevicesRequest> createRepeated() => $pb.PbList<ListDevicesRequest>();
  @$core.pragma('dart2js:noInline')
  static ListDevicesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListDevicesRequest>(create);
  static ListDevicesRequest? _defaultInstance;

  /// If true, only return devices currently reachable on the local
  /// network (mDNS-visible or an open connection); if false, return
  /// all known paired devices including offline ones.
  @$pb.TagNumber(1)
  $core.bool get onlineOnly => $_getBF(0);
  @$pb.TagNumber(1)
  set onlineOnly($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOnlineOnly() => $_has(0);
  @$pb.TagNumber(1)
  void clearOnlineOnly() => clearField(1);
}

class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    Identity? identity,
    $core.bool? online,
    $fixnum.Int64? pairedAtMs,
    $fixnum.Int64? lastSeenMs,
  }) {
    final $result = create();
    if (identity != null) {
      $result.identity = identity;
    }
    if (online != null) {
      $result.online = online;
    }
    if (pairedAtMs != null) {
      $result.pairedAtMs = pairedAtMs;
    }
    if (lastSeenMs != null) {
      $result.lastSeenMs = lastSeenMs;
    }
    return $result;
  }
  DeviceInfo._() : super();
  factory DeviceInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOM<Identity>(1, _omitFieldNames ? '' : 'identity', subBuilder: Identity.create)
    ..aOB(2, _omitFieldNames ? '' : 'online')
    ..aInt64(3, _omitFieldNames ? '' : 'pairedAtMs')
    ..aInt64(4, _omitFieldNames ? '' : 'lastSeenMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceInfo clone() => DeviceInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceInfo copyWith(void Function(DeviceInfo) updates) => super.copyWith((message) => updates(message as DeviceInfo)) as DeviceInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfo create() => DeviceInfo._();
  DeviceInfo createEmptyInstance() => create();
  static $pb.PbList<DeviceInfo> createRepeated() => $pb.PbList<DeviceInfo>();
  @$core.pragma('dart2js:noInline')
  static DeviceInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceInfo>(create);
  static DeviceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  Identity get identity => $_getN(0);
  @$pb.TagNumber(1)
  set identity(Identity v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentity() => clearField(1);
  @$pb.TagNumber(1)
  Identity ensureIdentity() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get online => $_getBF(1);
  @$pb.TagNumber(2)
  set online($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOnline() => $_has(1);
  @$pb.TagNumber(2)
  void clearOnline() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get pairedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set pairedAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPairedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearPairedAtMs() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastSeenMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastSeenMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastSeenMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastSeenMs() => clearField(4);
}

class ListDevicesResponse extends $pb.GeneratedMessage {
  factory ListDevicesResponse({
    $core.Iterable<DeviceInfo>? devices,
  }) {
    final $result = create();
    if (devices != null) {
      $result.devices.addAll(devices);
    }
    return $result;
  }
  ListDevicesResponse._() : super();
  factory ListDevicesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ListDevicesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ListDevicesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..pc<DeviceInfo>(1, _omitFieldNames ? '' : 'devices', $pb.PbFieldType.PM, subBuilder: DeviceInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ListDevicesResponse clone() => ListDevicesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ListDevicesResponse copyWith(void Function(ListDevicesResponse) updates) => super.copyWith((message) => updates(message as ListDevicesResponse)) as ListDevicesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListDevicesResponse create() => ListDevicesResponse._();
  ListDevicesResponse createEmptyInstance() => create();
  static $pb.PbList<ListDevicesResponse> createRepeated() => $pb.PbList<ListDevicesResponse>();
  @$core.pragma('dart2js:noInline')
  static ListDevicesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListDevicesResponse>(create);
  static ListDevicesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<DeviceInfo> get devices => $_getList(0);
}

/// Loopback-only (see "Local UI messages" section below): asks the local
/// daemon to drop its live-connection attribution for a paired device,
/// so it stops being reported as online purely because it holds an open
/// SyncStream (it may still show online afterward if mDNS-visible -- see
/// DeviceInfo.online / ListDevices comment). This does not forcibly tear
/// down the peer's underlying transport; the peer's next reconnect (or
/// re-sent Identity frame) simply re-establishes the attribution.
class DisconnectDeviceRequest extends $pb.GeneratedMessage {
  factory DisconnectDeviceRequest({
    $core.String? deviceId,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    return $result;
  }
  DisconnectDeviceRequest._() : super();
  factory DisconnectDeviceRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DisconnectDeviceRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DisconnectDeviceRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DisconnectDeviceRequest clone() => DisconnectDeviceRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DisconnectDeviceRequest copyWith(void Function(DisconnectDeviceRequest) updates) => super.copyWith((message) => updates(message as DisconnectDeviceRequest)) as DisconnectDeviceRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DisconnectDeviceRequest create() => DisconnectDeviceRequest._();
  DisconnectDeviceRequest createEmptyInstance() => create();
  static $pb.PbList<DisconnectDeviceRequest> createRepeated() => $pb.PbList<DisconnectDeviceRequest>();
  @$core.pragma('dart2js:noInline')
  static DisconnectDeviceRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DisconnectDeviceRequest>(create);
  static DisconnectDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);
}

class DisconnectDeviceResponse extends $pb.GeneratedMessage {
  factory DisconnectDeviceResponse({
    $core.bool? wasConnected,
  }) {
    final $result = create();
    if (wasConnected != null) {
      $result.wasConnected = wasConnected;
    }
    return $result;
  }
  DisconnectDeviceResponse._() : super();
  factory DisconnectDeviceResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DisconnectDeviceResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DisconnectDeviceResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'wasConnected')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DisconnectDeviceResponse clone() => DisconnectDeviceResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DisconnectDeviceResponse copyWith(void Function(DisconnectDeviceResponse) updates) => super.copyWith((message) => updates(message as DisconnectDeviceResponse)) as DisconnectDeviceResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DisconnectDeviceResponse create() => DisconnectDeviceResponse._();
  DisconnectDeviceResponse createEmptyInstance() => create();
  static $pb.PbList<DisconnectDeviceResponse> createRepeated() => $pb.PbList<DisconnectDeviceResponse>();
  @$core.pragma('dart2js:noInline')
  static DisconnectDeviceResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DisconnectDeviceResponse>(create);
  static DisconnectDeviceResponse? _defaultInstance;

  /// True if a live SyncStream connection for this device_id was found
  /// and its attribution dropped; false if it was not currently
  /// connected (not an error -- disconnecting an already-offline device
  /// is a no-op).
  @$pb.TagNumber(1)
  $core.bool get wasConnected => $_getBF(0);
  @$pb.TagNumber(1)
  set wasConnected($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasWasConnected() => $_has(0);
  @$pb.TagNumber(1)
  void clearWasConnected() => clearField(1);
}

/// Loopback-only (see "Local UI messages" section below): the local UI's
/// "Forget device" action (T-307). Unlike DisconnectDevice, this
/// permanently removes the device's row from the paired-devices store,
/// so it no longer appears in ListDevices at all and re-establishing a
/// connection requires a fresh Pair/ConfirmPin PIN exchange (T-015's
/// duplicate-pairing short-circuit no longer applies once forgotten).
class ForgetDeviceRequest extends $pb.GeneratedMessage {
  factory ForgetDeviceRequest({
    $core.String? deviceId,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    return $result;
  }
  ForgetDeviceRequest._() : super();
  factory ForgetDeviceRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ForgetDeviceRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ForgetDeviceRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ForgetDeviceRequest clone() => ForgetDeviceRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ForgetDeviceRequest copyWith(void Function(ForgetDeviceRequest) updates) => super.copyWith((message) => updates(message as ForgetDeviceRequest)) as ForgetDeviceRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ForgetDeviceRequest create() => ForgetDeviceRequest._();
  ForgetDeviceRequest createEmptyInstance() => create();
  static $pb.PbList<ForgetDeviceRequest> createRepeated() => $pb.PbList<ForgetDeviceRequest>();
  @$core.pragma('dart2js:noInline')
  static ForgetDeviceRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ForgetDeviceRequest>(create);
  static ForgetDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);
}

class ForgetDeviceResponse extends $pb.GeneratedMessage {
  factory ForgetDeviceResponse({
    $core.bool? removed,
  }) {
    final $result = create();
    if (removed != null) {
      $result.removed = removed;
    }
    return $result;
  }
  ForgetDeviceResponse._() : super();
  factory ForgetDeviceResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ForgetDeviceResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ForgetDeviceResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'removed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ForgetDeviceResponse clone() => ForgetDeviceResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ForgetDeviceResponse copyWith(void Function(ForgetDeviceResponse) updates) => super.copyWith((message) => updates(message as ForgetDeviceResponse)) as ForgetDeviceResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ForgetDeviceResponse create() => ForgetDeviceResponse._();
  ForgetDeviceResponse createEmptyInstance() => create();
  static $pb.PbList<ForgetDeviceResponse> createRepeated() => $pb.PbList<ForgetDeviceResponse>();
  @$core.pragma('dart2js:noInline')
  static ForgetDeviceResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ForgetDeviceResponse>(create);
  static ForgetDeviceResponse? _defaultInstance;

  /// True if a paired device with this device_id was found and removed;
  /// false if it was already unknown (not an error -- forgetting an
  /// already-unpaired device is a no-op).
  @$pb.TagNumber(1)
  $core.bool get removed => $_getBF(0);
  @$pb.TagNumber(1)
  set removed($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRemoved() => $_has(0);
  @$pb.TagNumber(1)
  void clearRemoved() => clearField(1);
}

class PingRequest extends $pb.GeneratedMessage {
  factory PingRequest({
    $fixnum.Int64? sentAtMs,
  }) {
    final $result = create();
    if (sentAtMs != null) {
      $result.sentAtMs = sentAtMs;
    }
    return $result;
  }
  PingRequest._() : super();
  factory PingRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PingRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PingRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'sentAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PingRequest clone() => PingRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PingRequest copyWith(void Function(PingRequest) updates) => super.copyWith((message) => updates(message as PingRequest)) as PingRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PingRequest create() => PingRequest._();
  PingRequest createEmptyInstance() => create();
  static $pb.PbList<PingRequest> createRepeated() => $pb.PbList<PingRequest>();
  @$core.pragma('dart2js:noInline')
  static PingRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PingRequest>(create);
  static PingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sentAtMs => $_getI64(0);
  @$pb.TagNumber(1)
  set sentAtMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSentAtMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSentAtMs() => clearField(1);
}

class PongRequest extends $pb.GeneratedMessage {
  factory PongRequest({
    $fixnum.Int64? sentAtMs,
    $fixnum.Int64? repliedAtMs,
  }) {
    final $result = create();
    if (sentAtMs != null) {
      $result.sentAtMs = sentAtMs;
    }
    if (repliedAtMs != null) {
      $result.repliedAtMs = repliedAtMs;
    }
    return $result;
  }
  PongRequest._() : super();
  factory PongRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PongRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PongRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'sentAtMs')
    ..aInt64(2, _omitFieldNames ? '' : 'repliedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PongRequest clone() => PongRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PongRequest copyWith(void Function(PongRequest) updates) => super.copyWith((message) => updates(message as PongRequest)) as PongRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PongRequest create() => PongRequest._();
  PongRequest createEmptyInstance() => create();
  static $pb.PbList<PongRequest> createRepeated() => $pb.PbList<PongRequest>();
  @$core.pragma('dart2js:noInline')
  static PongRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PongRequest>(create);
  static PongRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sentAtMs => $_getI64(0);
  @$pb.TagNumber(1)
  set sentAtMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSentAtMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSentAtMs() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get repliedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set repliedAtMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRepliedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearRepliedAtMs() => clearField(2);
}

enum SyncFrame_Payload {
  clipboard, 
  inputEvent, 
  fileTransferStart, 
  fileChunk, 
  batteryStatus, 
  notification, 
  error, 
  identity, 
  fileChunkRequest, 
  notSet
}

/// A single bidirectional-stream frame. Exactly one of the fields below
/// is set per message (proto3 oneof enforces this and keeps the wire
/// format extensible -- adding SyncFrame case 9 later does not break
/// old parsers, which simply see an unset oneof).
class SyncFrame extends $pb.GeneratedMessage {
  factory SyncFrame({
    ClipboardData? clipboard,
    RemoteInputEvent? inputEvent,
    FileTransferStart? fileTransferStart,
    FileChunk? fileChunk,
    BatteryStatus? batteryStatus,
    NotificationData? notification,
    Error? error,
    Identity? identity,
    FileChunkRequest? fileChunkRequest,
  }) {
    final $result = create();
    if (clipboard != null) {
      $result.clipboard = clipboard;
    }
    if (inputEvent != null) {
      $result.inputEvent = inputEvent;
    }
    if (fileTransferStart != null) {
      $result.fileTransferStart = fileTransferStart;
    }
    if (fileChunk != null) {
      $result.fileChunk = fileChunk;
    }
    if (batteryStatus != null) {
      $result.batteryStatus = batteryStatus;
    }
    if (notification != null) {
      $result.notification = notification;
    }
    if (error != null) {
      $result.error = error;
    }
    if (identity != null) {
      $result.identity = identity;
    }
    if (fileChunkRequest != null) {
      $result.fileChunkRequest = fileChunkRequest;
    }
    return $result;
  }
  SyncFrame._() : super();
  factory SyncFrame.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SyncFrame.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, SyncFrame_Payload> _SyncFrame_PayloadByTag = {
    1 : SyncFrame_Payload.clipboard,
    2 : SyncFrame_Payload.inputEvent,
    3 : SyncFrame_Payload.fileTransferStart,
    4 : SyncFrame_Payload.fileChunk,
    5 : SyncFrame_Payload.batteryStatus,
    6 : SyncFrame_Payload.notification,
    7 : SyncFrame_Payload.error,
    8 : SyncFrame_Payload.identity,
    9 : SyncFrame_Payload.fileChunkRequest,
    0 : SyncFrame_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SyncFrame', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7, 8, 9])
    ..aOM<ClipboardData>(1, _omitFieldNames ? '' : 'clipboard', subBuilder: ClipboardData.create)
    ..aOM<RemoteInputEvent>(2, _omitFieldNames ? '' : 'inputEvent', subBuilder: RemoteInputEvent.create)
    ..aOM<FileTransferStart>(3, _omitFieldNames ? '' : 'fileTransferStart', subBuilder: FileTransferStart.create)
    ..aOM<FileChunk>(4, _omitFieldNames ? '' : 'fileChunk', subBuilder: FileChunk.create)
    ..aOM<BatteryStatus>(5, _omitFieldNames ? '' : 'batteryStatus', subBuilder: BatteryStatus.create)
    ..aOM<NotificationData>(6, _omitFieldNames ? '' : 'notification', subBuilder: NotificationData.create)
    ..aOM<Error>(7, _omitFieldNames ? '' : 'error', subBuilder: Error.create)
    ..aOM<Identity>(8, _omitFieldNames ? '' : 'identity', subBuilder: Identity.create)
    ..aOM<FileChunkRequest>(9, _omitFieldNames ? '' : 'fileChunkRequest', subBuilder: FileChunkRequest.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SyncFrame clone() => SyncFrame()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SyncFrame copyWith(void Function(SyncFrame) updates) => super.copyWith((message) => updates(message as SyncFrame)) as SyncFrame;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncFrame create() => SyncFrame._();
  SyncFrame createEmptyInstance() => create();
  static $pb.PbList<SyncFrame> createRepeated() => $pb.PbList<SyncFrame>();
  @$core.pragma('dart2js:noInline')
  static SyncFrame getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncFrame>(create);
  static SyncFrame? _defaultInstance;

  SyncFrame_Payload whichPayload() => _SyncFrame_PayloadByTag[$_whichOneof(0)]!;
  void clearPayload() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ClipboardData get clipboard => $_getN(0);
  @$pb.TagNumber(1)
  set clipboard(ClipboardData v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasClipboard() => $_has(0);
  @$pb.TagNumber(1)
  void clearClipboard() => clearField(1);
  @$pb.TagNumber(1)
  ClipboardData ensureClipboard() => $_ensure(0);

  @$pb.TagNumber(2)
  RemoteInputEvent get inputEvent => $_getN(1);
  @$pb.TagNumber(2)
  set inputEvent(RemoteInputEvent v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasInputEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearInputEvent() => clearField(2);
  @$pb.TagNumber(2)
  RemoteInputEvent ensureInputEvent() => $_ensure(1);

  @$pb.TagNumber(3)
  FileTransferStart get fileTransferStart => $_getN(2);
  @$pb.TagNumber(3)
  set fileTransferStart(FileTransferStart v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFileTransferStart() => $_has(2);
  @$pb.TagNumber(3)
  void clearFileTransferStart() => clearField(3);
  @$pb.TagNumber(3)
  FileTransferStart ensureFileTransferStart() => $_ensure(2);

  @$pb.TagNumber(4)
  FileChunk get fileChunk => $_getN(3);
  @$pb.TagNumber(4)
  set fileChunk(FileChunk v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasFileChunk() => $_has(3);
  @$pb.TagNumber(4)
  void clearFileChunk() => clearField(4);
  @$pb.TagNumber(4)
  FileChunk ensureFileChunk() => $_ensure(3);

  @$pb.TagNumber(5)
  BatteryStatus get batteryStatus => $_getN(4);
  @$pb.TagNumber(5)
  set batteryStatus(BatteryStatus v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasBatteryStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearBatteryStatus() => clearField(5);
  @$pb.TagNumber(5)
  BatteryStatus ensureBatteryStatus() => $_ensure(4);

  @$pb.TagNumber(6)
  NotificationData get notification => $_getN(5);
  @$pb.TagNumber(6)
  set notification(NotificationData v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasNotification() => $_has(5);
  @$pb.TagNumber(6)
  void clearNotification() => clearField(6);
  @$pb.TagNumber(6)
  NotificationData ensureNotification() => $_ensure(5);

  @$pb.TagNumber(7)
  Error get error => $_getN(6);
  @$pb.TagNumber(7)
  set error(Error v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => clearField(7);
  @$pb.TagNumber(7)
  Error ensureError() => $_ensure(6);

  @$pb.TagNumber(8)
  Identity get identity => $_getN(7);
  @$pb.TagNumber(8)
  set identity(Identity v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasIdentity() => $_has(7);
  @$pb.TagNumber(8)
  void clearIdentity() => clearField(8);
  @$pb.TagNumber(8)
  Identity ensureIdentity() => $_ensure(7);

  @$pb.TagNumber(9)
  FileChunkRequest get fileChunkRequest => $_getN(8);
  @$pb.TagNumber(9)
  set fileChunkRequest(FileChunkRequest v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasFileChunkRequest() => $_has(8);
  @$pb.TagNumber(9)
  void clearFileChunkRequest() => clearField(9);
  @$pb.TagNumber(9)
  FileChunkRequest ensureFileChunkRequest() => $_ensure(8);
}

class LocalEventsRequest extends $pb.GeneratedMessage {
  factory LocalEventsRequest() => create();
  LocalEventsRequest._() : super();
  factory LocalEventsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LocalEventsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LocalEventsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LocalEventsRequest clone() => LocalEventsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LocalEventsRequest copyWith(void Function(LocalEventsRequest) updates) => super.copyWith((message) => updates(message as LocalEventsRequest)) as LocalEventsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalEventsRequest create() => LocalEventsRequest._();
  LocalEventsRequest createEmptyInstance() => create();
  static $pb.PbList<LocalEventsRequest> createRepeated() => $pb.PbList<LocalEventsRequest>();
  @$core.pragma('dart2js:noInline')
  static LocalEventsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocalEventsRequest>(create);
  static LocalEventsRequest? _defaultInstance;
}

/// Emitted the moment a PairRequest arrives, so the local UI can show
/// the PIN dialog with a live countdown (T-014, T-036).
class PairingRequestedLocalEvent extends $pb.GeneratedMessage {
  factory PairingRequestedLocalEvent({
    $core.String? requesterDeviceId,
    $core.String? requesterDeviceName,
    $core.String? pinCode,
    $fixnum.Int64? pinExpiresAtMs,
  }) {
    final $result = create();
    if (requesterDeviceId != null) {
      $result.requesterDeviceId = requesterDeviceId;
    }
    if (requesterDeviceName != null) {
      $result.requesterDeviceName = requesterDeviceName;
    }
    if (pinCode != null) {
      $result.pinCode = pinCode;
    }
    if (pinExpiresAtMs != null) {
      $result.pinExpiresAtMs = pinExpiresAtMs;
    }
    return $result;
  }
  PairingRequestedLocalEvent._() : super();
  factory PairingRequestedLocalEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PairingRequestedLocalEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PairingRequestedLocalEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requesterDeviceId')
    ..aOS(2, _omitFieldNames ? '' : 'requesterDeviceName')
    ..aOS(3, _omitFieldNames ? '' : 'pinCode')
    ..aInt64(4, _omitFieldNames ? '' : 'pinExpiresAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PairingRequestedLocalEvent clone() => PairingRequestedLocalEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PairingRequestedLocalEvent copyWith(void Function(PairingRequestedLocalEvent) updates) => super.copyWith((message) => updates(message as PairingRequestedLocalEvent)) as PairingRequestedLocalEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairingRequestedLocalEvent create() => PairingRequestedLocalEvent._();
  PairingRequestedLocalEvent createEmptyInstance() => create();
  static $pb.PbList<PairingRequestedLocalEvent> createRepeated() => $pb.PbList<PairingRequestedLocalEvent>();
  @$core.pragma('dart2js:noInline')
  static PairingRequestedLocalEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PairingRequestedLocalEvent>(create);
  static PairingRequestedLocalEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requesterDeviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requesterDeviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequesterDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequesterDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get requesterDeviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set requesterDeviceName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequesterDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequesterDeviceName() => clearField(2);

  /// The 6-digit PIN the local user must read to the requester's user.
  /// Loopback-only (see section comment); never sent to the requester.
  @$pb.TagNumber(3)
  $core.String get pinCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set pinCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPinCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearPinCode() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get pinExpiresAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set pinExpiresAtMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPinExpiresAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinExpiresAtMs() => clearField(4);
}

/// One entry of the daemon's in-memory clipboard ring buffer (T-023),
/// exposed for the desktop UI's clipboard history panel (T-037).
class ClipboardHistoryEntry extends $pb.GeneratedMessage {
  factory ClipboardHistoryEntry({
    $core.String? content,
    $core.String? mimeType,
    $fixnum.Int64? capturedAtMs,
    $core.String? source,
  }) {
    final $result = create();
    if (content != null) {
      $result.content = content;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (capturedAtMs != null) {
      $result.capturedAtMs = capturedAtMs;
    }
    if (source != null) {
      $result.source = source;
    }
    return $result;
  }
  ClipboardHistoryEntry._() : super();
  factory ClipboardHistoryEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClipboardHistoryEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClipboardHistoryEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'content')
    ..aOS(2, _omitFieldNames ? '' : 'mimeType')
    ..aInt64(3, _omitFieldNames ? '' : 'capturedAtMs')
    ..aOS(4, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClipboardHistoryEntry clone() => ClipboardHistoryEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClipboardHistoryEntry copyWith(void Function(ClipboardHistoryEntry) updates) => super.copyWith((message) => updates(message as ClipboardHistoryEntry)) as ClipboardHistoryEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClipboardHistoryEntry create() => ClipboardHistoryEntry._();
  ClipboardHistoryEntry createEmptyInstance() => create();
  static $pb.PbList<ClipboardHistoryEntry> createRepeated() => $pb.PbList<ClipboardHistoryEntry>();
  @$core.pragma('dart2js:noInline')
  static ClipboardHistoryEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClipboardHistoryEntry>(create);
  static ClipboardHistoryEntry? _defaultInstance;

  /// MVP is text-only, so content is a string rather than bytes.
  @$pb.TagNumber(1)
  $core.String get content => $_getSZ(0);
  @$pb.TagNumber(1)
  set content($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimeType($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMimeType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimeType() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get capturedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set capturedAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCapturedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapturedAtMs() => clearField(3);

  /// "local" for entries captured from this machine's own clipboard,
  /// or the source peer's device_id for entries applied from remote.
  @$pb.TagNumber(4)
  $core.String get source => $_getSZ(3);
  @$pb.TagNumber(4)
  set source($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(4)
  void clearSource() => clearField(4);
}

/// Progress of an in-flight *incoming* file transfer (T-027), throttled
/// by the daemon so the UI is never flooded (at most ~4 updates/second
/// per transfer).
class TransferProgress extends $pb.GeneratedMessage {
  factory TransferProgress({
    $core.String? transferId,
    $core.String? fileName,
    $fixnum.Int64? bytesTransferred,
    $fixnum.Int64? totalBytes,
    $core.bool? completed,
    $core.bool? failed,
  }) {
    final $result = create();
    if (transferId != null) {
      $result.transferId = transferId;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (bytesTransferred != null) {
      $result.bytesTransferred = bytesTransferred;
    }
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    if (completed != null) {
      $result.completed = completed;
    }
    if (failed != null) {
      $result.failed = failed;
    }
    return $result;
  }
  TransferProgress._() : super();
  factory TransferProgress.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TransferProgress.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TransferProgress', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'transferId')
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aInt64(3, _omitFieldNames ? '' : 'bytesTransferred')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aOB(5, _omitFieldNames ? '' : 'completed')
    ..aOB(6, _omitFieldNames ? '' : 'failed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TransferProgress clone() => TransferProgress()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TransferProgress copyWith(void Function(TransferProgress) updates) => super.copyWith((message) => updates(message as TransferProgress)) as TransferProgress;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransferProgress create() => TransferProgress._();
  TransferProgress createEmptyInstance() => create();
  static $pb.PbList<TransferProgress> createRepeated() => $pb.PbList<TransferProgress>();
  @$core.pragma('dart2js:noInline')
  static TransferProgress getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TransferProgress>(create);
  static TransferProgress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get transferId => $_getSZ(0);
  @$pb.TagNumber(1)
  set transferId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransferId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesTransferred => $_getI64(2);
  @$pb.TagNumber(3)
  set bytesTransferred($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBytesTransferred() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytesTransferred() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => clearField(4);

  /// Exactly one of completed/failed is set on the final event.
  @$pb.TagNumber(5)
  $core.bool get completed => $_getBF(4);
  @$pb.TagNumber(5)
  set completed($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCompleted() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompleted() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get failed => $_getBF(5);
  @$pb.TagNumber(6)
  set failed($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFailed() => $_has(5);
  @$pb.TagNumber(6)
  void clearFailed() => clearField(6);
}

enum LocalEvent_Event {
  pairingRequested, 
  battery, 
  notification, 
  clipboard, 
  transferProgress, 
  notSet
}

/// One event on the SubscribeLocalEvents stream. Same oneof-envelope
/// pattern as SyncFrame: adding a case later is backward-compatible.
class LocalEvent extends $pb.GeneratedMessage {
  factory LocalEvent({
    PairingRequestedLocalEvent? pairingRequested,
    BatteryStatus? battery,
    NotificationData? notification,
    ClipboardHistoryEntry? clipboard,
    TransferProgress? transferProgress,
  }) {
    final $result = create();
    if (pairingRequested != null) {
      $result.pairingRequested = pairingRequested;
    }
    if (battery != null) {
      $result.battery = battery;
    }
    if (notification != null) {
      $result.notification = notification;
    }
    if (clipboard != null) {
      $result.clipboard = clipboard;
    }
    if (transferProgress != null) {
      $result.transferProgress = transferProgress;
    }
    return $result;
  }
  LocalEvent._() : super();
  factory LocalEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LocalEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, LocalEvent_Event> _LocalEvent_EventByTag = {
    1 : LocalEvent_Event.pairingRequested,
    2 : LocalEvent_Event.battery,
    3 : LocalEvent_Event.notification,
    4 : LocalEvent_Event.clipboard,
    5 : LocalEvent_Event.transferProgress,
    0 : LocalEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LocalEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOM<PairingRequestedLocalEvent>(1, _omitFieldNames ? '' : 'pairingRequested', subBuilder: PairingRequestedLocalEvent.create)
    ..aOM<BatteryStatus>(2, _omitFieldNames ? '' : 'battery', subBuilder: BatteryStatus.create)
    ..aOM<NotificationData>(3, _omitFieldNames ? '' : 'notification', subBuilder: NotificationData.create)
    ..aOM<ClipboardHistoryEntry>(4, _omitFieldNames ? '' : 'clipboard', subBuilder: ClipboardHistoryEntry.create)
    ..aOM<TransferProgress>(5, _omitFieldNames ? '' : 'transferProgress', subBuilder: TransferProgress.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LocalEvent clone() => LocalEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LocalEvent copyWith(void Function(LocalEvent) updates) => super.copyWith((message) => updates(message as LocalEvent)) as LocalEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalEvent create() => LocalEvent._();
  LocalEvent createEmptyInstance() => create();
  static $pb.PbList<LocalEvent> createRepeated() => $pb.PbList<LocalEvent>();
  @$core.pragma('dart2js:noInline')
  static LocalEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocalEvent>(create);
  static LocalEvent? _defaultInstance;

  LocalEvent_Event whichEvent() => _LocalEvent_EventByTag[$_whichOneof(0)]!;
  void clearEvent() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  PairingRequestedLocalEvent get pairingRequested => $_getN(0);
  @$pb.TagNumber(1)
  set pairingRequested(PairingRequestedLocalEvent v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPairingRequested() => $_has(0);
  @$pb.TagNumber(1)
  void clearPairingRequested() => clearField(1);
  @$pb.TagNumber(1)
  PairingRequestedLocalEvent ensurePairingRequested() => $_ensure(0);

  @$pb.TagNumber(2)
  BatteryStatus get battery => $_getN(1);
  @$pb.TagNumber(2)
  set battery(BatteryStatus v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasBattery() => $_has(1);
  @$pb.TagNumber(2)
  void clearBattery() => clearField(2);
  @$pb.TagNumber(2)
  BatteryStatus ensureBattery() => $_ensure(1);

  @$pb.TagNumber(3)
  NotificationData get notification => $_getN(2);
  @$pb.TagNumber(3)
  set notification(NotificationData v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasNotification() => $_has(2);
  @$pb.TagNumber(3)
  void clearNotification() => clearField(3);
  @$pb.TagNumber(3)
  NotificationData ensureNotification() => $_ensure(2);

  @$pb.TagNumber(4)
  ClipboardHistoryEntry get clipboard => $_getN(3);
  @$pb.TagNumber(4)
  set clipboard(ClipboardHistoryEntry v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasClipboard() => $_has(3);
  @$pb.TagNumber(4)
  void clearClipboard() => clearField(4);
  @$pb.TagNumber(4)
  ClipboardHistoryEntry ensureClipboard() => $_ensure(3);

  @$pb.TagNumber(5)
  TransferProgress get transferProgress => $_getN(4);
  @$pb.TagNumber(5)
  set transferProgress(TransferProgress v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasTransferProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransferProgress() => clearField(5);
  @$pb.TagNumber(5)
  TransferProgress ensureTransferProgress() => $_ensure(4);
}

class GetLocalStateRequest extends $pb.GeneratedMessage {
  factory GetLocalStateRequest() => create();
  GetLocalStateRequest._() : super();
  factory GetLocalStateRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetLocalStateRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetLocalStateRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetLocalStateRequest clone() => GetLocalStateRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetLocalStateRequest copyWith(void Function(GetLocalStateRequest) updates) => super.copyWith((message) => updates(message as GetLocalStateRequest)) as GetLocalStateRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetLocalStateRequest create() => GetLocalStateRequest._();
  GetLocalStateRequest createEmptyInstance() => create();
  static $pb.PbList<GetLocalStateRequest> createRepeated() => $pb.PbList<GetLocalStateRequest>();
  @$core.pragma('dart2js:noInline')
  static GetLocalStateRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetLocalStateRequest>(create);
  static GetLocalStateRequest? _defaultInstance;
}

/// A device currently visible via mDNS but not necessarily paired --
/// surfaced so the UI can offer a "pair with nearby device" action.
/// Distinct from DeviceInfo, which is reserved for paired devices
/// (see ListDevices / T-019).
class NearbyDevice extends $pb.GeneratedMessage {
  factory NearbyDevice({
    $core.String? deviceId,
    $core.String? deviceName,
    $core.String? platform,
    $core.String? addr,
    $core.int? port,
    $core.int? protocolVersion,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (addr != null) {
      $result.addr = addr;
    }
    if (port != null) {
      $result.port = port;
    }
    if (protocolVersion != null) {
      $result.protocolVersion = protocolVersion;
    }
    return $result;
  }
  NearbyDevice._() : super();
  factory NearbyDevice.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NearbyDevice.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NearbyDevice', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'addr')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'port', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'protocolVersion', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NearbyDevice clone() => NearbyDevice()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NearbyDevice copyWith(void Function(NearbyDevice) updates) => super.copyWith((message) => updates(message as NearbyDevice)) as NearbyDevice;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NearbyDevice create() => NearbyDevice._();
  NearbyDevice createEmptyInstance() => create();
  static $pb.PbList<NearbyDevice> createRepeated() => $pb.PbList<NearbyDevice>();
  @$core.pragma('dart2js:noInline')
  static NearbyDevice getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NearbyDevice>(create);
  static NearbyDevice? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => clearField(3);

  /// Peer address as an IP string plus port, ready for the UI's Rust
  /// core to dial for Pair/SyncStream.
  @$pb.TagNumber(4)
  $core.String get addr => $_getSZ(3);
  @$pb.TagNumber(4)
  set addr($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAddr() => $_has(3);
  @$pb.TagNumber(4)
  void clearAddr() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get port => $_getIZ(4);
  @$pb.TagNumber(5)
  set port($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPort() => $_has(4);
  @$pb.TagNumber(5)
  void clearPort() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get protocolVersion => $_getIZ(5);
  @$pb.TagNumber(6)
  set protocolVersion($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasProtocolVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearProtocolVersion() => clearField(6);
}

/// Snapshot of everything the local UI needs to render its panels on
/// startup; live updates then arrive via SubscribeLocalEvents.
class GetLocalStateResponse extends $pb.GeneratedMessage {
  factory GetLocalStateResponse({
    Identity? localIdentity,
    $core.Iterable<$core.String>? capabilities,
    $core.Iterable<ClipboardHistoryEntry>? clipboardHistory,
    BatteryStatus? latestBattery,
    $core.Iterable<NotificationData>? notifications,
    $core.Iterable<NearbyDevice>? nearbyDevices,
    $core.bool? remoteInputEnabled,
    $core.bool? clipboardSyncEnabled,
  }) {
    final $result = create();
    if (localIdentity != null) {
      $result.localIdentity = localIdentity;
    }
    if (capabilities != null) {
      $result.capabilities.addAll(capabilities);
    }
    if (clipboardHistory != null) {
      $result.clipboardHistory.addAll(clipboardHistory);
    }
    if (latestBattery != null) {
      $result.latestBattery = latestBattery;
    }
    if (notifications != null) {
      $result.notifications.addAll(notifications);
    }
    if (nearbyDevices != null) {
      $result.nearbyDevices.addAll(nearbyDevices);
    }
    if (remoteInputEnabled != null) {
      $result.remoteInputEnabled = remoteInputEnabled;
    }
    if (clipboardSyncEnabled != null) {
      $result.clipboardSyncEnabled = clipboardSyncEnabled;
    }
    return $result;
  }
  GetLocalStateResponse._() : super();
  factory GetLocalStateResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetLocalStateResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetLocalStateResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOM<Identity>(1, _omitFieldNames ? '' : 'localIdentity', subBuilder: Identity.create)
    ..pPS(2, _omitFieldNames ? '' : 'capabilities')
    ..pc<ClipboardHistoryEntry>(3, _omitFieldNames ? '' : 'clipboardHistory', $pb.PbFieldType.PM, subBuilder: ClipboardHistoryEntry.create)
    ..aOM<BatteryStatus>(4, _omitFieldNames ? '' : 'latestBattery', subBuilder: BatteryStatus.create)
    ..pc<NotificationData>(5, _omitFieldNames ? '' : 'notifications', $pb.PbFieldType.PM, subBuilder: NotificationData.create)
    ..pc<NearbyDevice>(6, _omitFieldNames ? '' : 'nearbyDevices', $pb.PbFieldType.PM, subBuilder: NearbyDevice.create)
    ..aOB(7, _omitFieldNames ? '' : 'remoteInputEnabled')
    ..aOB(8, _omitFieldNames ? '' : 'clipboardSyncEnabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetLocalStateResponse clone() => GetLocalStateResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetLocalStateResponse copyWith(void Function(GetLocalStateResponse) updates) => super.copyWith((message) => updates(message as GetLocalStateResponse)) as GetLocalStateResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetLocalStateResponse create() => GetLocalStateResponse._();
  GetLocalStateResponse createEmptyInstance() => create();
  static $pb.PbList<GetLocalStateResponse> createRepeated() => $pb.PbList<GetLocalStateResponse>();
  @$core.pragma('dart2js:noInline')
  static GetLocalStateResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetLocalStateResponse>(create);
  static GetLocalStateResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Identity get localIdentity => $_getN(0);
  @$pb.TagNumber(1)
  set localIdentity(Identity v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasLocalIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocalIdentity() => clearField(1);
  @$pb.TagNumber(1)
  Identity ensureLocalIdentity() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.String> get capabilities => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<ClipboardHistoryEntry> get clipboardHistory => $_getList(2);

  /// Unset if no battery report has been received from a peer yet.
  @$pb.TagNumber(4)
  BatteryStatus get latestBattery => $_getN(3);
  @$pb.TagNumber(4)
  set latestBattery(BatteryStatus v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasLatestBattery() => $_has(3);
  @$pb.TagNumber(4)
  void clearLatestBattery() => clearField(4);
  @$pb.TagNumber(4)
  BatteryStatus ensureLatestBattery() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.List<NotificationData> get notifications => $_getList(4);

  @$pb.TagNumber(6)
  $core.List<NearbyDevice> get nearbyDevices => $_getList(5);

  /// Whether incoming RemoteInputEvent frames are currently applied to
  /// the input backend (T-309). Always false when the "remote_input"
  /// capability is absent (no backend compiled/detected).
  @$pb.TagNumber(7)
  $core.bool get remoteInputEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set remoteInputEnabled($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasRemoteInputEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearRemoteInputEnabled() => clearField(7);

  /// Whether local clipboard changes are polled/broadcast and incoming
  /// ClipboardData frames are applied (T-310). Always false when the
  /// "clipboard" capability is absent.
  @$pb.TagNumber(8)
  $core.bool get clipboardSyncEnabled => $_getBF(7);
  @$pb.TagNumber(8)
  set clipboardSyncEnabled($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasClipboardSyncEnabled() => $_has(7);
  @$pb.TagNumber(8)
  void clearClipboardSyncEnabled() => clearField(8);
}

/// Loopback-only (see "Local UI messages" section): lets the local UI
/// gate whether incoming RemoteInputEvent frames are actually applied
/// to the input backend (T-309), without tearing down the SyncStream
/// connection itself.
class SetRemoteInputEnabledRequest extends $pb.GeneratedMessage {
  factory SetRemoteInputEnabledRequest({
    $core.bool? enabled,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    return $result;
  }
  SetRemoteInputEnabledRequest._() : super();
  factory SetRemoteInputEnabledRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SetRemoteInputEnabledRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SetRemoteInputEnabledRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SetRemoteInputEnabledRequest clone() => SetRemoteInputEnabledRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SetRemoteInputEnabledRequest copyWith(void Function(SetRemoteInputEnabledRequest) updates) => super.copyWith((message) => updates(message as SetRemoteInputEnabledRequest)) as SetRemoteInputEnabledRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetRemoteInputEnabledRequest create() => SetRemoteInputEnabledRequest._();
  SetRemoteInputEnabledRequest createEmptyInstance() => create();
  static $pb.PbList<SetRemoteInputEnabledRequest> createRepeated() => $pb.PbList<SetRemoteInputEnabledRequest>();
  @$core.pragma('dart2js:noInline')
  static SetRemoteInputEnabledRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetRemoteInputEnabledRequest>(create);
  static SetRemoteInputEnabledRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);
}

class SetRemoteInputEnabledResponse extends $pb.GeneratedMessage {
  factory SetRemoteInputEnabledResponse({
    $core.bool? enabled,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    return $result;
  }
  SetRemoteInputEnabledResponse._() : super();
  factory SetRemoteInputEnabledResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SetRemoteInputEnabledResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SetRemoteInputEnabledResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SetRemoteInputEnabledResponse clone() => SetRemoteInputEnabledResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SetRemoteInputEnabledResponse copyWith(void Function(SetRemoteInputEnabledResponse) updates) => super.copyWith((message) => updates(message as SetRemoteInputEnabledResponse)) as SetRemoteInputEnabledResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetRemoteInputEnabledResponse create() => SetRemoteInputEnabledResponse._();
  SetRemoteInputEnabledResponse createEmptyInstance() => create();
  static $pb.PbList<SetRemoteInputEnabledResponse> createRepeated() => $pb.PbList<SetRemoteInputEnabledResponse>();
  @$core.pragma('dart2js:noInline')
  static SetRemoteInputEnabledResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetRemoteInputEnabledResponse>(create);
  static SetRemoteInputEnabledResponse? _defaultInstance;

  /// Echoes the value now in effect. May differ from the request if no
  /// input backend is available (the daemon rejects the call instead --
  /// see the RPC comment -- but keeping this field mirrors
  /// SetClipboardSyncEnabledResponse for symmetry).
  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);
}

/// Loopback-only (see "Local UI messages" section): lets the local UI
/// (including the tray "Sync Clipboard" toggle, T-310) gate whether the
/// daemon polls/broadcasts local clipboard changes and applies incoming
/// ones, without disabling the clipboard backend entirely.
class SetClipboardSyncEnabledRequest extends $pb.GeneratedMessage {
  factory SetClipboardSyncEnabledRequest({
    $core.bool? enabled,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    return $result;
  }
  SetClipboardSyncEnabledRequest._() : super();
  factory SetClipboardSyncEnabledRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SetClipboardSyncEnabledRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SetClipboardSyncEnabledRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SetClipboardSyncEnabledRequest clone() => SetClipboardSyncEnabledRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SetClipboardSyncEnabledRequest copyWith(void Function(SetClipboardSyncEnabledRequest) updates) => super.copyWith((message) => updates(message as SetClipboardSyncEnabledRequest)) as SetClipboardSyncEnabledRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetClipboardSyncEnabledRequest create() => SetClipboardSyncEnabledRequest._();
  SetClipboardSyncEnabledRequest createEmptyInstance() => create();
  static $pb.PbList<SetClipboardSyncEnabledRequest> createRepeated() => $pb.PbList<SetClipboardSyncEnabledRequest>();
  @$core.pragma('dart2js:noInline')
  static SetClipboardSyncEnabledRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetClipboardSyncEnabledRequest>(create);
  static SetClipboardSyncEnabledRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);
}

class SetClipboardSyncEnabledResponse extends $pb.GeneratedMessage {
  factory SetClipboardSyncEnabledResponse({
    $core.bool? enabled,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    return $result;
  }
  SetClipboardSyncEnabledResponse._() : super();
  factory SetClipboardSyncEnabledResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SetClipboardSyncEnabledResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SetClipboardSyncEnabledResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SetClipboardSyncEnabledResponse clone() => SetClipboardSyncEnabledResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SetClipboardSyncEnabledResponse copyWith(void Function(SetClipboardSyncEnabledResponse) updates) => super.copyWith((message) => updates(message as SetClipboardSyncEnabledResponse)) as SetClipboardSyncEnabledResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetClipboardSyncEnabledResponse create() => SetClipboardSyncEnabledResponse._();
  SetClipboardSyncEnabledResponse createEmptyInstance() => create();
  static $pb.PbList<SetClipboardSyncEnabledResponse> createRepeated() => $pb.PbList<SetClipboardSyncEnabledResponse>();
  @$core.pragma('dart2js:noInline')
  static SetClipboardSyncEnabledResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetClipboardSyncEnabledResponse>(create);
  static SetClipboardSyncEnabledResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);
}

class GetPinnedFingerprintRequest extends $pb.GeneratedMessage {
  factory GetPinnedFingerprintRequest({
    $core.String? deviceId,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    return $result;
  }
  GetPinnedFingerprintRequest._() : super();
  factory GetPinnedFingerprintRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetPinnedFingerprintRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPinnedFingerprintRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetPinnedFingerprintRequest clone() => GetPinnedFingerprintRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetPinnedFingerprintRequest copyWith(void Function(GetPinnedFingerprintRequest) updates) => super.copyWith((message) => updates(message as GetPinnedFingerprintRequest)) as GetPinnedFingerprintRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPinnedFingerprintRequest create() => GetPinnedFingerprintRequest._();
  GetPinnedFingerprintRequest createEmptyInstance() => create();
  static $pb.PbList<GetPinnedFingerprintRequest> createRepeated() => $pb.PbList<GetPinnedFingerprintRequest>();
  @$core.pragma('dart2js:noInline')
  static GetPinnedFingerprintRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPinnedFingerprintRequest>(create);
  static GetPinnedFingerprintRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);
}

class GetPinnedFingerprintResponse extends $pb.GeneratedMessage {
  factory GetPinnedFingerprintResponse({
    $core.String? fingerprint,
  }) {
    final $result = create();
    if (fingerprint != null) {
      $result.fingerprint = fingerprint;
    }
    return $result;
  }
  GetPinnedFingerprintResponse._() : super();
  factory GetPinnedFingerprintResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetPinnedFingerprintResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPinnedFingerprintResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fingerprint')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetPinnedFingerprintResponse clone() => GetPinnedFingerprintResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetPinnedFingerprintResponse copyWith(void Function(GetPinnedFingerprintResponse) updates) => super.copyWith((message) => updates(message as GetPinnedFingerprintResponse)) as GetPinnedFingerprintResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPinnedFingerprintResponse create() => GetPinnedFingerprintResponse._();
  GetPinnedFingerprintResponse createEmptyInstance() => create();
  static $pb.PbList<GetPinnedFingerprintResponse> createRepeated() => $pb.PbList<GetPinnedFingerprintResponse>();
  @$core.pragma('dart2js:noInline')
  static GetPinnedFingerprintResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPinnedFingerprintResponse>(create);
  static GetPinnedFingerprintResponse? _defaultInstance;

  /// Empty string means "no pin yet" (unknown device, or a pre-TOFU
  /// device awaiting record-on-first-use backfill, T-C5).
  @$pb.TagNumber(1)
  $core.String get fingerprint => $_getSZ(0);
  @$pb.TagNumber(1)
  set fingerprint($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFingerprint() => $_has(0);
  @$pb.TagNumber(1)
  void clearFingerprint() => clearField(1);
}

class RecordFingerprintRequest extends $pb.GeneratedMessage {
  factory RecordFingerprintRequest({
    $core.String? deviceId,
    $core.String? fingerprint,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (fingerprint != null) {
      $result.fingerprint = fingerprint;
    }
    return $result;
  }
  RecordFingerprintRequest._() : super();
  factory RecordFingerprintRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RecordFingerprintRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RecordFingerprintRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'fingerprint')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RecordFingerprintRequest clone() => RecordFingerprintRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RecordFingerprintRequest copyWith(void Function(RecordFingerprintRequest) updates) => super.copyWith((message) => updates(message as RecordFingerprintRequest)) as RecordFingerprintRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RecordFingerprintRequest create() => RecordFingerprintRequest._();
  RecordFingerprintRequest createEmptyInstance() => create();
  static $pb.PbList<RecordFingerprintRequest> createRepeated() => $pb.PbList<RecordFingerprintRequest>();
  @$core.pragma('dart2js:noInline')
  static RecordFingerprintRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RecordFingerprintRequest>(create);
  static RecordFingerprintRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fingerprint => $_getSZ(1);
  @$pb.TagNumber(2)
  set fingerprint($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFingerprint() => $_has(1);
  @$pb.TagNumber(2)
  void clearFingerprint() => clearField(2);
}

class RecordFingerprintResponse extends $pb.GeneratedMessage {
  factory RecordFingerprintResponse({
    $core.bool? recorded,
  }) {
    final $result = create();
    if (recorded != null) {
      $result.recorded = recorded;
    }
    return $result;
  }
  RecordFingerprintResponse._() : super();
  factory RecordFingerprintResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RecordFingerprintResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RecordFingerprintResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'recorded')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RecordFingerprintResponse clone() => RecordFingerprintResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RecordFingerprintResponse copyWith(void Function(RecordFingerprintResponse) updates) => super.copyWith((message) => updates(message as RecordFingerprintResponse)) as RecordFingerprintResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RecordFingerprintResponse create() => RecordFingerprintResponse._();
  RecordFingerprintResponse createEmptyInstance() => create();
  static $pb.PbList<RecordFingerprintResponse> createRepeated() => $pb.PbList<RecordFingerprintResponse>();
  @$core.pragma('dart2js:noInline')
  static RecordFingerprintResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RecordFingerprintResponse>(create);
  static RecordFingerprintResponse? _defaultInstance;

  /// False if the device_id is not a known paired device (nothing pinned).
  @$pb.TagNumber(1)
  $core.bool get recorded => $_getBF(0);
  @$pb.TagNumber(1)
  set recorded($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRecorded() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecorded() => clearField(1);
}

class RunDiagnosticsRequest extends $pb.GeneratedMessage {
  factory RunDiagnosticsRequest({
    $core.String? checkId,
  }) {
    final $result = create();
    if (checkId != null) {
      $result.checkId = checkId;
    }
    return $result;
  }
  RunDiagnosticsRequest._() : super();
  factory RunDiagnosticsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RunDiagnosticsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RunDiagnosticsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'checkId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RunDiagnosticsRequest clone() => RunDiagnosticsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RunDiagnosticsRequest copyWith(void Function(RunDiagnosticsRequest) updates) => super.copyWith((message) => updates(message as RunDiagnosticsRequest)) as RunDiagnosticsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RunDiagnosticsRequest create() => RunDiagnosticsRequest._();
  RunDiagnosticsRequest createEmptyInstance() => create();
  static $pb.PbList<RunDiagnosticsRequest> createRepeated() => $pb.PbList<RunDiagnosticsRequest>();
  @$core.pragma('dart2js:noInline')
  static RunDiagnosticsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RunDiagnosticsRequest>(create);
  static RunDiagnosticsRequest? _defaultInstance;

  /// Run only this check id; empty = run every check.
  @$pb.TagNumber(1)
  $core.String get checkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set checkId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCheckId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCheckId() => clearField(1);
}

/// One check outcome. `category` is one of "environment" | "network" |
/// "pairing" | "features"; `status` is one of "ok" | "warn" | "error".
class DiagnosticCheck extends $pb.GeneratedMessage {
  factory DiagnosticCheck({
    $core.String? id,
    $core.String? title,
    $core.String? category,
    $core.String? status,
    $core.String? summary,
    $core.String? detail,
    $core.String? remediation,
    $core.Map<$core.String, $core.String>? data,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (title != null) {
      $result.title = title;
    }
    if (category != null) {
      $result.category = category;
    }
    if (status != null) {
      $result.status = status;
    }
    if (summary != null) {
      $result.summary = summary;
    }
    if (detail != null) {
      $result.detail = detail;
    }
    if (remediation != null) {
      $result.remediation = remediation;
    }
    if (data != null) {
      $result.data.addAll(data);
    }
    return $result;
  }
  DiagnosticCheck._() : super();
  factory DiagnosticCheck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DiagnosticCheck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DiagnosticCheck', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'category')
    ..aOS(4, _omitFieldNames ? '' : 'status')
    ..aOS(5, _omitFieldNames ? '' : 'summary')
    ..aOS(6, _omitFieldNames ? '' : 'detail')
    ..aOS(7, _omitFieldNames ? '' : 'remediation')
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'data', entryClassName: 'DiagnosticCheck.DataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('connectible.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DiagnosticCheck clone() => DiagnosticCheck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DiagnosticCheck copyWith(void Function(DiagnosticCheck) updates) => super.copyWith((message) => updates(message as DiagnosticCheck)) as DiagnosticCheck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiagnosticCheck create() => DiagnosticCheck._();
  DiagnosticCheck createEmptyInstance() => create();
  static $pb.PbList<DiagnosticCheck> createRepeated() => $pb.PbList<DiagnosticCheck>();
  @$core.pragma('dart2js:noInline')
  static DiagnosticCheck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiagnosticCheck>(create);
  static DiagnosticCheck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get category => $_getSZ(2);
  @$pb.TagNumber(3)
  set category($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get status => $_getSZ(3);
  @$pb.TagNumber(4)
  set status($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get summary => $_getSZ(4);
  @$pb.TagNumber(5)
  set summary($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSummary() => $_has(4);
  @$pb.TagNumber(5)
  void clearSummary() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get detail => $_getSZ(5);
  @$pb.TagNumber(6)
  set detail($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDetail() => $_has(5);
  @$pb.TagNumber(6)
  void clearDetail() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get remediation => $_getSZ(6);
  @$pb.TagNumber(7)
  set remediation($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasRemediation() => $_has(6);
  @$pb.TagNumber(7)
  void clearRemediation() => clearField(7);

  @$pb.TagNumber(8)
  $core.Map<$core.String, $core.String> get data => $_getMap(7);
}

class RunDiagnosticsResponse extends $pb.GeneratedMessage {
  factory RunDiagnosticsResponse({
    $core.Iterable<DiagnosticCheck>? checks,
    $core.String? worst,
  }) {
    final $result = create();
    if (checks != null) {
      $result.checks.addAll(checks);
    }
    if (worst != null) {
      $result.worst = worst;
    }
    return $result;
  }
  RunDiagnosticsResponse._() : super();
  factory RunDiagnosticsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RunDiagnosticsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RunDiagnosticsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'connectible.v1'), createEmptyInstance: create)
    ..pc<DiagnosticCheck>(1, _omitFieldNames ? '' : 'checks', $pb.PbFieldType.PM, subBuilder: DiagnosticCheck.create)
    ..aOS(2, _omitFieldNames ? '' : 'worst')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RunDiagnosticsResponse clone() => RunDiagnosticsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RunDiagnosticsResponse copyWith(void Function(RunDiagnosticsResponse) updates) => super.copyWith((message) => updates(message as RunDiagnosticsResponse)) as RunDiagnosticsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RunDiagnosticsResponse create() => RunDiagnosticsResponse._();
  RunDiagnosticsResponse createEmptyInstance() => create();
  static $pb.PbList<RunDiagnosticsResponse> createRepeated() => $pb.PbList<RunDiagnosticsResponse>();
  @$core.pragma('dart2js:noInline')
  static RunDiagnosticsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RunDiagnosticsResponse>(create);
  static RunDiagnosticsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<DiagnosticCheck> get checks => $_getList(0);

  /// Worst severity across all returned checks ("ok" | "warn" | "error").
  @$pb.TagNumber(2)
  $core.String get worst => $_getSZ(1);
  @$pb.TagNumber(2)
  set worst($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWorst() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorst() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
