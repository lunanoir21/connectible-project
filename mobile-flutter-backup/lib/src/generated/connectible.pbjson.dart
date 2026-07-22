//
//  Generated code. Do not modify.
//  source: connectible.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use platformDescriptor instead')
const Platform$json = {
  '1': 'Platform',
  '2': [
    {'1': 'PLATFORM_UNSPECIFIED', '2': 0},
    {'1': 'PLATFORM_LINUX_X11', '2': 1},
    {'1': 'PLATFORM_LINUX_WAYLAND', '2': 2},
    {'1': 'PLATFORM_WINDOWS', '2': 3},
    {'1': 'PLATFORM_MACOS', '2': 4},
    {'1': 'PLATFORM_ANDROID', '2': 5},
    {'1': 'PLATFORM_IOS', '2': 6},
  ],
};

/// Descriptor for `Platform`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List platformDescriptor = $convert.base64Decode(
    'CghQbGF0Zm9ybRIYChRQTEFURk9STV9VTlNQRUNJRklFRBAAEhYKElBMQVRGT1JNX0xJTlVYX1'
    'gxMRABEhoKFlBMQVRGT1JNX0xJTlVYX1dBWUxBTkQQAhIUChBQTEFURk9STV9XSU5ET1dTEAMS'
    'EgoOUExBVEZPUk1fTUFDT1MQBBIUChBQTEFURk9STV9BTkRST0lEEAUSEAoMUExBVEZPUk1fSU'
    '9TEAY=');

@$core.Deprecated('Use deviceTypeDescriptor instead')
const DeviceType$json = {
  '1': 'DeviceType',
  '2': [
    {'1': 'DEVICE_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'DEVICE_TYPE_DESKTOP', '2': 1},
    {'1': 'DEVICE_TYPE_LAPTOP', '2': 2},
    {'1': 'DEVICE_TYPE_PHONE', '2': 3},
    {'1': 'DEVICE_TYPE_TABLET', '2': 4},
  ],
};

/// Descriptor for `DeviceType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List deviceTypeDescriptor = $convert.base64Decode(
    'CgpEZXZpY2VUeXBlEhsKF0RFVklDRV9UWVBFX1VOU1BFQ0lGSUVEEAASFwoTREVWSUNFX1RZUE'
    'VfREVTS1RPUBABEhYKEkRFVklDRV9UWVBFX0xBUFRPUBACEhUKEURFVklDRV9UWVBFX1BIT05F'
    'EAMSFgoSREVWSUNFX1RZUEVfVEFCTEVUEAQ=');

@$core.Deprecated('Use inputEventTypeDescriptor instead')
const InputEventType$json = {
  '1': 'InputEventType',
  '2': [
    {'1': 'INPUT_EVENT_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'INPUT_EVENT_TYPE_MOUSE_MOVE', '2': 1},
    {'1': 'INPUT_EVENT_TYPE_MOUSE_BUTTON', '2': 2},
    {'1': 'INPUT_EVENT_TYPE_MOUSE_SCROLL', '2': 3},
    {'1': 'INPUT_EVENT_TYPE_KEY', '2': 4},
  ],
};

/// Descriptor for `InputEventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List inputEventTypeDescriptor = $convert.base64Decode(
    'Cg5JbnB1dEV2ZW50VHlwZRIgChxJTlBVVF9FVkVOVF9UWVBFX1VOU1BFQ0lGSUVEEAASHwobSU'
    '5QVVRfRVZFTlRfVFlQRV9NT1VTRV9NT1ZFEAESIQodSU5QVVRfRVZFTlRfVFlQRV9NT1VTRV9C'
    'VVRUT04QAhIhCh1JTlBVVF9FVkVOVF9UWVBFX01PVVNFX1NDUk9MTBADEhgKFElOUFVUX0VWRU'
    '5UX1RZUEVfS0VZEAQ=');

@$core.Deprecated('Use mouseButtonDescriptor instead')
const MouseButton$json = {
  '1': 'MouseButton',
  '2': [
    {'1': 'MOUSE_BUTTON_UNSPECIFIED', '2': 0},
    {'1': 'MOUSE_BUTTON_LEFT', '2': 1},
    {'1': 'MOUSE_BUTTON_MIDDLE', '2': 2},
    {'1': 'MOUSE_BUTTON_RIGHT', '2': 3},
  ],
};

/// Descriptor for `MouseButton`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List mouseButtonDescriptor = $convert.base64Decode(
    'CgtNb3VzZUJ1dHRvbhIcChhNT1VTRV9CVVRUT05fVU5TUEVDSUZJRUQQABIVChFNT1VTRV9CVV'
    'RUT05fTEVGVBABEhcKE01PVVNFX0JVVFRPTl9NSURETEUQAhIWChJNT1VTRV9CVVRUT05fUklH'
    'SFQQAw==');

@$core.Deprecated('Use errorCodeDescriptor instead')
const ErrorCode$json = {
  '1': 'ErrorCode',
  '2': [
    {'1': 'ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'ERROR_CODE_UNAUTHENTICATED', '2': 1},
    {'1': 'ERROR_CODE_PAIRING_REJECTED', '2': 2},
    {'1': 'ERROR_CODE_PAIRING_TIMEOUT', '2': 3},
    {'1': 'ERROR_CODE_DEVICE_NOT_FOUND', '2': 4},
    {'1': 'ERROR_CODE_FILE_TRANSFER_FAILED', '2': 5},
    {'1': 'ERROR_CODE_CHECKSUM_MISMATCH', '2': 6},
    {'1': 'ERROR_CODE_UNSUPPORTED_PLATFORM', '2': 7},
    {'1': 'ERROR_CODE_INTERNAL', '2': 8},
    {'1': 'ERROR_CODE_PROTOCOL_VERSION_MISMATCH', '2': 9},
    {'1': 'ERROR_CODE_RATE_LIMITED', '2': 10},
    {'1': 'ERROR_CODE_FINGERPRINT_CHANGED', '2': 11},
  ],
};

/// Descriptor for `ErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List errorCodeDescriptor = $convert.base64Decode(
    'CglFcnJvckNvZGUSGgoWRVJST1JfQ09ERV9VTlNQRUNJRklFRBAAEh4KGkVSUk9SX0NPREVfVU'
    '5BVVRIRU5USUNBVEVEEAESHwobRVJST1JfQ09ERV9QQUlSSU5HX1JFSkVDVEVEEAISHgoaRVJS'
    'T1JfQ09ERV9QQUlSSU5HX1RJTUVPVVQQAxIfChtFUlJPUl9DT0RFX0RFVklDRV9OT1RfRk9VTk'
    'QQBBIjCh9FUlJPUl9DT0RFX0ZJTEVfVFJBTlNGRVJfRkFJTEVEEAUSIAocRVJST1JfQ09ERV9D'
    'SEVDS1NVTV9NSVNNQVRDSBAGEiMKH0VSUk9SX0NPREVfVU5TVVBQT1JURURfUExBVEZPUk0QBx'
    'IXChNFUlJPUl9DT0RFX0lOVEVSTkFMEAgSKAokRVJST1JfQ09ERV9QUk9UT0NPTF9WRVJTSU9O'
    'X01JU01BVENIEAkSGwoXRVJST1JfQ09ERV9SQVRFX0xJTUlURUQQChIiCh5FUlJPUl9DT0RFX0'
    'ZJTkdFUlBSSU5UX0NIQU5HRUQQCw==');

@$core.Deprecated('Use identityDescriptor instead')
const Identity$json = {
  '1': 'Identity',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'device_name', '3': 2, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'platform', '3': 3, '4': 1, '5': 14, '6': '.connectible.v1.Platform', '10': 'platform'},
    {'1': 'device_type', '3': 4, '4': 1, '5': 14, '6': '.connectible.v1.DeviceType', '10': 'deviceType'},
    {'1': 'protocol_version', '3': 5, '4': 1, '5': 13, '10': 'protocolVersion'},
    {'1': 'app_version', '3': 6, '4': 1, '5': 9, '10': 'appVersion'},
    {'1': 'capabilities', '3': 7, '4': 3, '5': 9, '10': 'capabilities'},
  ],
};

/// Descriptor for `Identity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityDescriptor = $convert.base64Decode(
    'CghJZGVudGl0eRIbCglkZXZpY2VfaWQYASABKAlSCGRldmljZUlkEh8KC2RldmljZV9uYW1lGA'
    'IgASgJUgpkZXZpY2VOYW1lEjQKCHBsYXRmb3JtGAMgASgOMhguY29ubmVjdGlibGUudjEuUGxh'
    'dGZvcm1SCHBsYXRmb3JtEjsKC2RldmljZV90eXBlGAQgASgOMhouY29ubmVjdGlibGUudjEuRG'
    'V2aWNlVHlwZVIKZGV2aWNlVHlwZRIpChBwcm90b2NvbF92ZXJzaW9uGAUgASgNUg9wcm90b2Nv'
    'bFZlcnNpb24SHwoLYXBwX3ZlcnNpb24YBiABKAlSCmFwcFZlcnNpb24SIgoMY2FwYWJpbGl0aW'
    'VzGAcgAygJUgxjYXBhYmlsaXRpZXM=');

@$core.Deprecated('Use clipboardDataDescriptor instead')
const ClipboardData$json = {
  '1': 'ClipboardData',
  '2': [
    {'1': 'mime_type', '3': 1, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'content', '3': 2, '4': 1, '5': 12, '10': 'content'},
    {'1': 'captured_at_ms', '3': 3, '4': 1, '5': 3, '10': 'capturedAtMs'},
    {'1': 'content_hash', '3': 4, '4': 1, '5': 9, '10': 'contentHash'},
  ],
};

/// Descriptor for `ClipboardData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clipboardDataDescriptor = $convert.base64Decode(
    'Cg1DbGlwYm9hcmREYXRhEhsKCW1pbWVfdHlwZRgBIAEoCVIIbWltZVR5cGUSGAoHY29udGVudB'
    'gCIAEoDFIHY29udGVudBIkCg5jYXB0dXJlZF9hdF9tcxgDIAEoA1IMY2FwdHVyZWRBdE1zEiEK'
    'DGNvbnRlbnRfaGFzaBgEIAEoCVILY29udGVudEhhc2g=');

@$core.Deprecated('Use remoteInputEventDescriptor instead')
const RemoteInputEvent$json = {
  '1': 'RemoteInputEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.connectible.v1.InputEventType', '10': 'type'},
    {'1': 'x', '3': 2, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 2, '10': 'y'},
    {'1': 'button', '3': 4, '4': 1, '5': 14, '6': '.connectible.v1.MouseButton', '10': 'button'},
    {'1': 'pressed', '3': 5, '4': 1, '5': 8, '10': 'pressed'},
    {'1': 'scroll_delta_x', '3': 6, '4': 1, '5': 2, '10': 'scrollDeltaX'},
    {'1': 'scroll_delta_y', '3': 7, '4': 1, '5': 2, '10': 'scrollDeltaY'},
    {'1': 'key_code', '3': 8, '4': 1, '5': 13, '10': 'keyCode'},
    {'1': 'key_pressed', '3': 9, '4': 1, '5': 8, '10': 'keyPressed'},
    {'1': 'modifiers', '3': 10, '4': 1, '5': 13, '10': 'modifiers'},
  ],
};

/// Descriptor for `RemoteInputEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List remoteInputEventDescriptor = $convert.base64Decode(
    'ChBSZW1vdGVJbnB1dEV2ZW50EjIKBHR5cGUYASABKA4yHi5jb25uZWN0aWJsZS52MS5JbnB1dE'
    'V2ZW50VHlwZVIEdHlwZRIMCgF4GAIgASgCUgF4EgwKAXkYAyABKAJSAXkSMwoGYnV0dG9uGAQg'
    'ASgOMhsuY29ubmVjdGlibGUudjEuTW91c2VCdXR0b25SBmJ1dHRvbhIYCgdwcmVzc2VkGAUgAS'
    'gIUgdwcmVzc2VkEiQKDnNjcm9sbF9kZWx0YV94GAYgASgCUgxzY3JvbGxEZWx0YVgSJAoOc2Ny'
    'b2xsX2RlbHRhX3kYByABKAJSDHNjcm9sbERlbHRhWRIZCghrZXlfY29kZRgIIAEoDVIHa2V5Q2'
    '9kZRIfCgtrZXlfcHJlc3NlZBgJIAEoCFIKa2V5UHJlc3NlZBIcCgltb2RpZmllcnMYCiABKA1S'
    'CW1vZGlmaWVycw==');

@$core.Deprecated('Use fileTransferStartDescriptor instead')
const FileTransferStart$json = {
  '1': 'FileTransferStart',
  '2': [
    {'1': 'transfer_id', '3': 1, '4': 1, '5': 9, '10': 'transferId'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'file_size_bytes', '3': 3, '4': 1, '5': 3, '10': 'fileSizeBytes'},
    {'1': 'file_hash', '3': 4, '4': 1, '5': 9, '10': 'fileHash'},
    {'1': 'chunk_size_bytes', '3': 5, '4': 1, '5': 13, '10': 'chunkSizeBytes'},
    {'1': 'resume_offset_bytes', '3': 6, '4': 1, '5': 3, '10': 'resumeOffsetBytes'},
    {'1': 'mime_type', '3': 7, '4': 1, '5': 9, '10': 'mimeType'},
  ],
};

/// Descriptor for `FileTransferStart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileTransferStartDescriptor = $convert.base64Decode(
    'ChFGaWxlVHJhbnNmZXJTdGFydBIfCgt0cmFuc2Zlcl9pZBgBIAEoCVIKdHJhbnNmZXJJZBIbCg'
    'lmaWxlX25hbWUYAiABKAlSCGZpbGVOYW1lEiYKD2ZpbGVfc2l6ZV9ieXRlcxgDIAEoA1INZmls'
    'ZVNpemVCeXRlcxIbCglmaWxlX2hhc2gYBCABKAlSCGZpbGVIYXNoEigKEGNodW5rX3NpemVfYn'
    'l0ZXMYBSABKA1SDmNodW5rU2l6ZUJ5dGVzEi4KE3Jlc3VtZV9vZmZzZXRfYnl0ZXMYBiABKANS'
    'EXJlc3VtZU9mZnNldEJ5dGVzEhsKCW1pbWVfdHlwZRgHIAEoCVIIbWltZVR5cGU=');

@$core.Deprecated('Use fileChunkDescriptor instead')
const FileChunk$json = {
  '1': 'FileChunk',
  '2': [
    {'1': 'transfer_id', '3': 1, '4': 1, '5': 9, '10': 'transferId'},
    {'1': 'offset_bytes', '3': 2, '4': 1, '5': 3, '10': 'offsetBytes'},
    {'1': 'data', '3': 3, '4': 1, '5': 12, '10': 'data'},
    {'1': 'is_last', '3': 4, '4': 1, '5': 8, '10': 'isLast'},
    {'1': 'chunk_checksum', '3': 5, '4': 1, '5': 13, '10': 'chunkChecksum'},
  ],
};

/// Descriptor for `FileChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileChunkDescriptor = $convert.base64Decode(
    'CglGaWxlQ2h1bmsSHwoLdHJhbnNmZXJfaWQYASABKAlSCnRyYW5zZmVySWQSIQoMb2Zmc2V0X2'
    'J5dGVzGAIgASgDUgtvZmZzZXRCeXRlcxISCgRkYXRhGAMgASgMUgRkYXRhEhcKB2lzX2xhc3QY'
    'BCABKAhSBmlzTGFzdBIlCg5jaHVua19jaGVja3N1bRgFIAEoDVINY2h1bmtDaGVja3N1bQ==');

@$core.Deprecated('Use batteryStatusDescriptor instead')
const BatteryStatus$json = {
  '1': 'BatteryStatus',
  '2': [
    {'1': 'percentage', '3': 1, '4': 1, '5': 13, '10': 'percentage'},
    {'1': 'is_charging', '3': 2, '4': 1, '5': 8, '10': 'isCharging'},
    {'1': 'minutes_remaining', '3': 3, '4': 1, '5': 5, '10': 'minutesRemaining'},
    {'1': 'reported_at_ms', '3': 4, '4': 1, '5': 3, '10': 'reportedAtMs'},
  ],
};

/// Descriptor for `BatteryStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List batteryStatusDescriptor = $convert.base64Decode(
    'Cg1CYXR0ZXJ5U3RhdHVzEh4KCnBlcmNlbnRhZ2UYASABKA1SCnBlcmNlbnRhZ2USHwoLaXNfY2'
    'hhcmdpbmcYAiABKAhSCmlzQ2hhcmdpbmcSKwoRbWludXRlc19yZW1haW5pbmcYAyABKAVSEG1p'
    'bnV0ZXNSZW1haW5pbmcSJAoOcmVwb3J0ZWRfYXRfbXMYBCABKANSDHJlcG9ydGVkQXRNcw==');

@$core.Deprecated('Use notificationDataDescriptor instead')
const NotificationData$json = {
  '1': 'NotificationData',
  '2': [
    {'1': 'notification_id', '3': 1, '4': 1, '5': 9, '10': 'notificationId'},
    {'1': 'app_name', '3': 2, '4': 1, '5': 9, '10': 'appName'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'body', '3': 4, '4': 1, '5': 9, '10': 'body'},
    {'1': 'icon', '3': 5, '4': 1, '5': 12, '10': 'icon'},
    {'1': 'posted_at_ms', '3': 6, '4': 1, '5': 3, '10': 'postedAtMs'},
    {'1': 'is_dismissal', '3': 7, '4': 1, '5': 8, '10': 'isDismissal'},
  ],
};

/// Descriptor for `NotificationData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List notificationDataDescriptor = $convert.base64Decode(
    'ChBOb3RpZmljYXRpb25EYXRhEicKD25vdGlmaWNhdGlvbl9pZBgBIAEoCVIObm90aWZpY2F0aW'
    '9uSWQSGQoIYXBwX25hbWUYAiABKAlSB2FwcE5hbWUSFAoFdGl0bGUYAyABKAlSBXRpdGxlEhIK'
    'BGJvZHkYBCABKAlSBGJvZHkSEgoEaWNvbhgFIAEoDFIEaWNvbhIgCgxwb3N0ZWRfYXRfbXMYBi'
    'ABKANSCnBvc3RlZEF0TXMSIQoMaXNfZGlzbWlzc2FsGAcgASgIUgtpc0Rpc21pc3NhbA==');

@$core.Deprecated('Use errorDescriptor instead')
const Error$json = {
  '1': 'Error',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 14, '6': '.connectible.v1.ErrorCode', '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'details', '3': 3, '4': 3, '5': 11, '6': '.connectible.v1.Error.DetailsEntry', '10': 'details'},
  ],
  '3': [Error_DetailsEntry$json],
};

@$core.Deprecated('Use errorDescriptor instead')
const Error_DetailsEntry$json = {
  '1': 'DetailsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `Error`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDescriptor = $convert.base64Decode(
    'CgVFcnJvchItCgRjb2RlGAEgASgOMhkuY29ubmVjdGlibGUudjEuRXJyb3JDb2RlUgRjb2RlEh'
    'gKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2USPAoHZGV0YWlscxgDIAMoCzIiLmNvbm5lY3RpYmxl'
    'LnYxLkVycm9yLkRldGFpbHNFbnRyeVIHZGV0YWlscxo6CgxEZXRhaWxzRW50cnkSEAoDa2V5GA'
    'EgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AQ==');

@$core.Deprecated('Use fileChunkRequestDescriptor instead')
const FileChunkRequest$json = {
  '1': 'FileChunkRequest',
  '2': [
    {'1': 'transfer_id', '3': 1, '4': 1, '5': 9, '10': 'transferId'},
    {'1': 'offset_bytes', '3': 2, '4': 1, '5': 3, '10': 'offsetBytes'},
  ],
};

/// Descriptor for `FileChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileChunkRequestDescriptor = $convert.base64Decode(
    'ChBGaWxlQ2h1bmtSZXF1ZXN0Eh8KC3RyYW5zZmVyX2lkGAEgASgJUgp0cmFuc2ZlcklkEiEKDG'
    '9mZnNldF9ieXRlcxgCIAEoA1ILb2Zmc2V0Qnl0ZXM=');

@$core.Deprecated('Use uploadFileMetaDescriptor instead')
const UploadFileMeta$json = {
  '1': 'UploadFileMeta',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'file_size_bytes', '3': 3, '4': 1, '5': 3, '10': 'fileSizeBytes'},
    {'1': 'file_hash', '3': 4, '4': 1, '5': 9, '10': 'fileHash'},
    {'1': 'mime_type', '3': 5, '4': 1, '5': 9, '10': 'mimeType'},
  ],
};

/// Descriptor for `UploadFileMeta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFileMetaDescriptor = $convert.base64Decode(
    'Cg5VcGxvYWRGaWxlTWV0YRIXCgdmaWxlX2lkGAEgASgJUgZmaWxlSWQSGwoJZmlsZV9uYW1lGA'
    'IgASgJUghmaWxlTmFtZRImCg9maWxlX3NpemVfYnl0ZXMYAyABKANSDWZpbGVTaXplQnl0ZXMS'
    'GwoJZmlsZV9oYXNoGAQgASgJUghmaWxlSGFzaBIbCgltaW1lX3R5cGUYBSABKAlSCG1pbWVUeX'
    'Bl');

@$core.Deprecated('Use prepareUploadRequestDescriptor instead')
const PrepareUploadRequest$json = {
  '1': 'PrepareUploadRequest',
  '2': [
    {'1': 'sender', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.Identity', '10': 'sender'},
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'files', '3': 3, '4': 3, '5': 11, '6': '.connectible.v1.UploadFileMeta', '10': 'files'},
  ],
};

/// Descriptor for `PrepareUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareUploadRequestDescriptor = $convert.base64Decode(
    'ChRQcmVwYXJlVXBsb2FkUmVxdWVzdBIwCgZzZW5kZXIYASABKAsyGC5jb25uZWN0aWJsZS52MS'
    '5JZGVudGl0eVIGc2VuZGVyEh0KCnNlc3Npb25faWQYAiABKAlSCXNlc3Npb25JZBI0CgVmaWxl'
    'cxgDIAMoCzIeLmNvbm5lY3RpYmxlLnYxLlVwbG9hZEZpbGVNZXRhUgVmaWxlcw==');

@$core.Deprecated('Use uploadFileOfferDescriptor instead')
const UploadFileOffer$json = {
  '1': 'UploadFileOffer',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'accepted', '3': 2, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'resume_offset_bytes', '3': 3, '4': 1, '5': 3, '10': 'resumeOffsetBytes'},
    {'1': 'token', '3': 4, '4': 1, '5': 9, '10': 'token'},
    {'1': 'reject_reason', '3': 5, '4': 1, '5': 9, '10': 'rejectReason'},
  ],
};

/// Descriptor for `UploadFileOffer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFileOfferDescriptor = $convert.base64Decode(
    'Cg9VcGxvYWRGaWxlT2ZmZXISFwoHZmlsZV9pZBgBIAEoCVIGZmlsZUlkEhoKCGFjY2VwdGVkGA'
    'IgASgIUghhY2NlcHRlZBIuChNyZXN1bWVfb2Zmc2V0X2J5dGVzGAMgASgDUhFyZXN1bWVPZmZz'
    'ZXRCeXRlcxIUCgV0b2tlbhgEIAEoCVIFdG9rZW4SIwoNcmVqZWN0X3JlYXNvbhgFIAEoCVIMcm'
    'VqZWN0UmVhc29u');

@$core.Deprecated('Use prepareUploadResponseDescriptor instead')
const PrepareUploadResponse$json = {
  '1': 'PrepareUploadResponse',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'offers', '3': 2, '4': 3, '5': 11, '6': '.connectible.v1.UploadFileOffer', '10': 'offers'},
  ],
};

/// Descriptor for `PrepareUploadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareUploadResponseDescriptor = $convert.base64Decode(
    'ChVQcmVwYXJlVXBsb2FkUmVzcG9uc2USHQoKc2Vzc2lvbl9pZBgBIAEoCVIJc2Vzc2lvbklkEj'
    'cKBm9mZmVycxgCIAMoCzIfLmNvbm5lY3RpYmxlLnYxLlVwbG9hZEZpbGVPZmZlclIGb2ZmZXJz');

@$core.Deprecated('Use uploadFileHeaderDescriptor instead')
const UploadFileHeader$json = {
  '1': 'UploadFileHeader',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'file_id', '3': 2, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'token', '3': 3, '4': 1, '5': 9, '10': 'token'},
    {'1': 'offset_bytes', '3': 4, '4': 1, '5': 3, '10': 'offsetBytes'},
  ],
};

/// Descriptor for `UploadFileHeader`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFileHeaderDescriptor = $convert.base64Decode(
    'ChBVcGxvYWRGaWxlSGVhZGVyEh0KCnNlc3Npb25faWQYASABKAlSCXNlc3Npb25JZBIXCgdmaW'
    'xlX2lkGAIgASgJUgZmaWxlSWQSFAoFdG9rZW4YAyABKAlSBXRva2VuEiEKDG9mZnNldF9ieXRl'
    'cxgEIAEoA1ILb2Zmc2V0Qnl0ZXM=');

@$core.Deprecated('Use uploadFilePartDescriptor instead')
const UploadFilePart$json = {
  '1': 'UploadFilePart',
  '2': [
    {'1': 'header', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.UploadFileHeader', '9': 0, '10': 'header'},
    {'1': 'chunk', '3': 2, '4': 1, '5': 12, '9': 0, '10': 'chunk'},
  ],
  '8': [
    {'1': 'part'},
  ],
};

/// Descriptor for `UploadFilePart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFilePartDescriptor = $convert.base64Decode(
    'Cg5VcGxvYWRGaWxlUGFydBI6CgZoZWFkZXIYASABKAsyIC5jb25uZWN0aWJsZS52MS5VcGxvYW'
    'RGaWxlSGVhZGVySABSBmhlYWRlchIWCgVjaHVuaxgCIAEoDEgAUgVjaHVua0IGCgRwYXJ0');

@$core.Deprecated('Use uploadFileResultDescriptor instead')
const UploadFileResult$json = {
  '1': 'UploadFileResult',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'completed', '3': 2, '4': 1, '5': 8, '10': 'completed'},
    {'1': 'bytes_received', '3': 3, '4': 1, '5': 3, '10': 'bytesReceived'},
    {'1': 'hash_ok', '3': 4, '4': 1, '5': 8, '10': 'hashOk'},
  ],
};

/// Descriptor for `UploadFileResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadFileResultDescriptor = $convert.base64Decode(
    'ChBVcGxvYWRGaWxlUmVzdWx0EhcKB2ZpbGVfaWQYASABKAlSBmZpbGVJZBIcCgljb21wbGV0ZW'
    'QYAiABKAhSCWNvbXBsZXRlZBIlCg5ieXRlc19yZWNlaXZlZBgDIAEoA1INYnl0ZXNSZWNlaXZl'
    'ZBIXCgdoYXNoX29rGAQgASgIUgZoYXNoT2s=');

@$core.Deprecated('Use pairRequestDescriptor instead')
const PairRequest$json = {
  '1': 'PairRequest',
  '2': [
    {'1': 'requester', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.Identity', '10': 'requester'},
  ],
};

/// Descriptor for `PairRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairRequestDescriptor = $convert.base64Decode(
    'CgtQYWlyUmVxdWVzdBI2CglyZXF1ZXN0ZXIYASABKAsyGC5jb25uZWN0aWJsZS52MS5JZGVudG'
    'l0eVIJcmVxdWVzdGVy');

@$core.Deprecated('Use pairResponseDescriptor instead')
const PairResponse$json = {
  '1': 'PairResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'pin_expires_at_ms', '3': 2, '4': 1, '5': 3, '10': 'pinExpiresAtMs'},
    {'1': 'error', '3': 3, '4': 1, '5': 11, '6': '.connectible.v1.Error', '10': 'error'},
  ],
};

/// Descriptor for `PairResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairResponseDescriptor = $convert.base64Decode(
    'CgxQYWlyUmVzcG9uc2USGgoIYWNjZXB0ZWQYASABKAhSCGFjY2VwdGVkEikKEXBpbl9leHBpcm'
    'VzX2F0X21zGAIgASgDUg5waW5FeHBpcmVzQXRNcxIrCgVlcnJvchgDIAEoCzIVLmNvbm5lY3Rp'
    'YmxlLnYxLkVycm9yUgVlcnJvcg==');

@$core.Deprecated('Use confirmPinRequestDescriptor instead')
const ConfirmPinRequest$json = {
  '1': 'ConfirmPinRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'pin_code', '3': 2, '4': 1, '5': 9, '10': 'pinCode'},
  ],
};

/// Descriptor for `ConfirmPinRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPinRequestDescriptor = $convert.base64Decode(
    'ChFDb25maXJtUGluUmVxdWVzdBIbCglkZXZpY2VfaWQYASABKAlSCGRldmljZUlkEhkKCHBpbl'
    '9jb2RlGAIgASgJUgdwaW5Db2Rl');

@$core.Deprecated('Use confirmPinResponseDescriptor instead')
const ConfirmPinResponse$json = {
  '1': 'ConfirmPinResponse',
  '2': [
    {'1': 'verified', '3': 1, '4': 1, '5': 8, '10': 'verified'},
    {'1': 'error', '3': 2, '4': 1, '5': 11, '6': '.connectible.v1.Error', '10': 'error'},
  ],
};

/// Descriptor for `ConfirmPinResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPinResponseDescriptor = $convert.base64Decode(
    'ChJDb25maXJtUGluUmVzcG9uc2USGgoIdmVyaWZpZWQYASABKAhSCHZlcmlmaWVkEisKBWVycm'
    '9yGAIgASgLMhUuY29ubmVjdGlibGUudjEuRXJyb3JSBWVycm9y');

@$core.Deprecated('Use listDevicesRequestDescriptor instead')
const ListDevicesRequest$json = {
  '1': 'ListDevicesRequest',
  '2': [
    {'1': 'online_only', '3': 1, '4': 1, '5': 8, '10': 'onlineOnly'},
  ],
};

/// Descriptor for `ListDevicesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesRequestDescriptor = $convert.base64Decode(
    'ChJMaXN0RGV2aWNlc1JlcXVlc3QSHwoLb25saW5lX29ubHkYASABKAhSCm9ubGluZU9ubHk=');

@$core.Deprecated('Use deviceInfoDescriptor instead')
const DeviceInfo$json = {
  '1': 'DeviceInfo',
  '2': [
    {'1': 'identity', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.Identity', '10': 'identity'},
    {'1': 'online', '3': 2, '4': 1, '5': 8, '10': 'online'},
    {'1': 'paired_at_ms', '3': 3, '4': 1, '5': 3, '10': 'pairedAtMs'},
    {'1': 'last_seen_ms', '3': 4, '4': 1, '5': 3, '10': 'lastSeenMs'},
  ],
};

/// Descriptor for `DeviceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceInfoDescriptor = $convert.base64Decode(
    'CgpEZXZpY2VJbmZvEjQKCGlkZW50aXR5GAEgASgLMhguY29ubmVjdGlibGUudjEuSWRlbnRpdH'
    'lSCGlkZW50aXR5EhYKBm9ubGluZRgCIAEoCFIGb25saW5lEiAKDHBhaXJlZF9hdF9tcxgDIAEo'
    'A1IKcGFpcmVkQXRNcxIgCgxsYXN0X3NlZW5fbXMYBCABKANSCmxhc3RTZWVuTXM=');

@$core.Deprecated('Use listDevicesResponseDescriptor instead')
const ListDevicesResponse$json = {
  '1': 'ListDevicesResponse',
  '2': [
    {'1': 'devices', '3': 1, '4': 3, '5': 11, '6': '.connectible.v1.DeviceInfo', '10': 'devices'},
  ],
};

/// Descriptor for `ListDevicesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0RGV2aWNlc1Jlc3BvbnNlEjQKB2RldmljZXMYASADKAsyGi5jb25uZWN0aWJsZS52MS'
    '5EZXZpY2VJbmZvUgdkZXZpY2Vz');

@$core.Deprecated('Use disconnectDeviceRequestDescriptor instead')
const DisconnectDeviceRequest$json = {
  '1': 'DisconnectDeviceRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `DisconnectDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectDeviceRequestDescriptor = $convert.base64Decode(
    'ChdEaXNjb25uZWN0RGV2aWNlUmVxdWVzdBIbCglkZXZpY2VfaWQYASABKAlSCGRldmljZUlk');

@$core.Deprecated('Use disconnectDeviceResponseDescriptor instead')
const DisconnectDeviceResponse$json = {
  '1': 'DisconnectDeviceResponse',
  '2': [
    {'1': 'was_connected', '3': 1, '4': 1, '5': 8, '10': 'wasConnected'},
  ],
};

/// Descriptor for `DisconnectDeviceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectDeviceResponseDescriptor = $convert.base64Decode(
    'ChhEaXNjb25uZWN0RGV2aWNlUmVzcG9uc2USIwoNd2FzX2Nvbm5lY3RlZBgBIAEoCFIMd2FzQ2'
    '9ubmVjdGVk');

@$core.Deprecated('Use forgetDeviceRequestDescriptor instead')
const ForgetDeviceRequest$json = {
  '1': 'ForgetDeviceRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `ForgetDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetDeviceRequestDescriptor = $convert.base64Decode(
    'ChNGb3JnZXREZXZpY2VSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQ=');

@$core.Deprecated('Use forgetDeviceResponseDescriptor instead')
const ForgetDeviceResponse$json = {
  '1': 'ForgetDeviceResponse',
  '2': [
    {'1': 'removed', '3': 1, '4': 1, '5': 8, '10': 'removed'},
  ],
};

/// Descriptor for `ForgetDeviceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetDeviceResponseDescriptor = $convert.base64Decode(
    'ChRGb3JnZXREZXZpY2VSZXNwb25zZRIYCgdyZW1vdmVkGAEgASgIUgdyZW1vdmVk');

@$core.Deprecated('Use pingRequestDescriptor instead')
const PingRequest$json = {
  '1': 'PingRequest',
  '2': [
    {'1': 'sent_at_ms', '3': 1, '4': 1, '5': 3, '10': 'sentAtMs'},
  ],
};

/// Descriptor for `PingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingRequestDescriptor = $convert.base64Decode(
    'CgtQaW5nUmVxdWVzdBIcCgpzZW50X2F0X21zGAEgASgDUghzZW50QXRNcw==');

@$core.Deprecated('Use pongRequestDescriptor instead')
const PongRequest$json = {
  '1': 'PongRequest',
  '2': [
    {'1': 'sent_at_ms', '3': 1, '4': 1, '5': 3, '10': 'sentAtMs'},
    {'1': 'replied_at_ms', '3': 2, '4': 1, '5': 3, '10': 'repliedAtMs'},
  ],
};

/// Descriptor for `PongRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pongRequestDescriptor = $convert.base64Decode(
    'CgtQb25nUmVxdWVzdBIcCgpzZW50X2F0X21zGAEgASgDUghzZW50QXRNcxIiCg1yZXBsaWVkX2'
    'F0X21zGAIgASgDUgtyZXBsaWVkQXRNcw==');

@$core.Deprecated('Use syncFrameDescriptor instead')
const SyncFrame$json = {
  '1': 'SyncFrame',
  '2': [
    {'1': 'clipboard', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.ClipboardData', '9': 0, '10': 'clipboard'},
    {'1': 'input_event', '3': 2, '4': 1, '5': 11, '6': '.connectible.v1.RemoteInputEvent', '9': 0, '10': 'inputEvent'},
    {'1': 'file_transfer_start', '3': 3, '4': 1, '5': 11, '6': '.connectible.v1.FileTransferStart', '9': 0, '10': 'fileTransferStart'},
    {'1': 'file_chunk', '3': 4, '4': 1, '5': 11, '6': '.connectible.v1.FileChunk', '9': 0, '10': 'fileChunk'},
    {'1': 'battery_status', '3': 5, '4': 1, '5': 11, '6': '.connectible.v1.BatteryStatus', '9': 0, '10': 'batteryStatus'},
    {'1': 'notification', '3': 6, '4': 1, '5': 11, '6': '.connectible.v1.NotificationData', '9': 0, '10': 'notification'},
    {'1': 'error', '3': 7, '4': 1, '5': 11, '6': '.connectible.v1.Error', '9': 0, '10': 'error'},
    {'1': 'identity', '3': 8, '4': 1, '5': 11, '6': '.connectible.v1.Identity', '9': 0, '10': 'identity'},
    {'1': 'file_chunk_request', '3': 9, '4': 1, '5': 11, '6': '.connectible.v1.FileChunkRequest', '9': 0, '10': 'fileChunkRequest'},
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `SyncFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncFrameDescriptor = $convert.base64Decode(
    'CglTeW5jRnJhbWUSPQoJY2xpcGJvYXJkGAEgASgLMh0uY29ubmVjdGlibGUudjEuQ2xpcGJvYX'
    'JkRGF0YUgAUgljbGlwYm9hcmQSQwoLaW5wdXRfZXZlbnQYAiABKAsyIC5jb25uZWN0aWJsZS52'
    'MS5SZW1vdGVJbnB1dEV2ZW50SABSCmlucHV0RXZlbnQSUwoTZmlsZV90cmFuc2Zlcl9zdGFydB'
    'gDIAEoCzIhLmNvbm5lY3RpYmxlLnYxLkZpbGVUcmFuc2ZlclN0YXJ0SABSEWZpbGVUcmFuc2Zl'
    'clN0YXJ0EjoKCmZpbGVfY2h1bmsYBCABKAsyGS5jb25uZWN0aWJsZS52MS5GaWxlQ2h1bmtIAF'
    'IJZmlsZUNodW5rEkYKDmJhdHRlcnlfc3RhdHVzGAUgASgLMh0uY29ubmVjdGlibGUudjEuQmF0'
    'dGVyeVN0YXR1c0gAUg1iYXR0ZXJ5U3RhdHVzEkYKDG5vdGlmaWNhdGlvbhgGIAEoCzIgLmNvbm'
    '5lY3RpYmxlLnYxLk5vdGlmaWNhdGlvbkRhdGFIAFIMbm90aWZpY2F0aW9uEi0KBWVycm9yGAcg'
    'ASgLMhUuY29ubmVjdGlibGUudjEuRXJyb3JIAFIFZXJyb3ISNgoIaWRlbnRpdHkYCCABKAsyGC'
    '5jb25uZWN0aWJsZS52MS5JZGVudGl0eUgAUghpZGVudGl0eRJQChJmaWxlX2NodW5rX3JlcXVl'
    'c3QYCSABKAsyIC5jb25uZWN0aWJsZS52MS5GaWxlQ2h1bmtSZXF1ZXN0SABSEGZpbGVDaHVua1'
    'JlcXVlc3RCCQoHcGF5bG9hZA==');

@$core.Deprecated('Use localEventsRequestDescriptor instead')
const LocalEventsRequest$json = {
  '1': 'LocalEventsRequest',
};

/// Descriptor for `LocalEventsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localEventsRequestDescriptor = $convert.base64Decode(
    'ChJMb2NhbEV2ZW50c1JlcXVlc3Q=');

@$core.Deprecated('Use pairingRequestedLocalEventDescriptor instead')
const PairingRequestedLocalEvent$json = {
  '1': 'PairingRequestedLocalEvent',
  '2': [
    {'1': 'requester_device_id', '3': 1, '4': 1, '5': 9, '10': 'requesterDeviceId'},
    {'1': 'requester_device_name', '3': 2, '4': 1, '5': 9, '10': 'requesterDeviceName'},
    {'1': 'pin_code', '3': 3, '4': 1, '5': 9, '10': 'pinCode'},
    {'1': 'pin_expires_at_ms', '3': 4, '4': 1, '5': 3, '10': 'pinExpiresAtMs'},
  ],
};

/// Descriptor for `PairingRequestedLocalEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairingRequestedLocalEventDescriptor = $convert.base64Decode(
    'ChpQYWlyaW5nUmVxdWVzdGVkTG9jYWxFdmVudBIuChNyZXF1ZXN0ZXJfZGV2aWNlX2lkGAEgAS'
    'gJUhFyZXF1ZXN0ZXJEZXZpY2VJZBIyChVyZXF1ZXN0ZXJfZGV2aWNlX25hbWUYAiABKAlSE3Jl'
    'cXVlc3RlckRldmljZU5hbWUSGQoIcGluX2NvZGUYAyABKAlSB3BpbkNvZGUSKQoRcGluX2V4cG'
    'lyZXNfYXRfbXMYBCABKANSDnBpbkV4cGlyZXNBdE1z');

@$core.Deprecated('Use clipboardHistoryEntryDescriptor instead')
const ClipboardHistoryEntry$json = {
  '1': 'ClipboardHistoryEntry',
  '2': [
    {'1': 'content', '3': 1, '4': 1, '5': 9, '10': 'content'},
    {'1': 'mime_type', '3': 2, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'captured_at_ms', '3': 3, '4': 1, '5': 3, '10': 'capturedAtMs'},
    {'1': 'source', '3': 4, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ClipboardHistoryEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clipboardHistoryEntryDescriptor = $convert.base64Decode(
    'ChVDbGlwYm9hcmRIaXN0b3J5RW50cnkSGAoHY29udGVudBgBIAEoCVIHY29udGVudBIbCgltaW'
    '1lX3R5cGUYAiABKAlSCG1pbWVUeXBlEiQKDmNhcHR1cmVkX2F0X21zGAMgASgDUgxjYXB0dXJl'
    'ZEF0TXMSFgoGc291cmNlGAQgASgJUgZzb3VyY2U=');

@$core.Deprecated('Use transferProgressDescriptor instead')
const TransferProgress$json = {
  '1': 'TransferProgress',
  '2': [
    {'1': 'transfer_id', '3': 1, '4': 1, '5': 9, '10': 'transferId'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'bytes_transferred', '3': 3, '4': 1, '5': 3, '10': 'bytesTransferred'},
    {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
    {'1': 'completed', '3': 5, '4': 1, '5': 8, '10': 'completed'},
    {'1': 'failed', '3': 6, '4': 1, '5': 8, '10': 'failed'},
  ],
};

/// Descriptor for `TransferProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferProgressDescriptor = $convert.base64Decode(
    'ChBUcmFuc2ZlclByb2dyZXNzEh8KC3RyYW5zZmVyX2lkGAEgASgJUgp0cmFuc2ZlcklkEhsKCW'
    'ZpbGVfbmFtZRgCIAEoCVIIZmlsZU5hbWUSKwoRYnl0ZXNfdHJhbnNmZXJyZWQYAyABKANSEGJ5'
    'dGVzVHJhbnNmZXJyZWQSHwoLdG90YWxfYnl0ZXMYBCABKANSCnRvdGFsQnl0ZXMSHAoJY29tcG'
    'xldGVkGAUgASgIUgljb21wbGV0ZWQSFgoGZmFpbGVkGAYgASgIUgZmYWlsZWQ=');

@$core.Deprecated('Use localEventDescriptor instead')
const LocalEvent$json = {
  '1': 'LocalEvent',
  '2': [
    {'1': 'pairing_requested', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.PairingRequestedLocalEvent', '9': 0, '10': 'pairingRequested'},
    {'1': 'battery', '3': 2, '4': 1, '5': 11, '6': '.connectible.v1.BatteryStatus', '9': 0, '10': 'battery'},
    {'1': 'notification', '3': 3, '4': 1, '5': 11, '6': '.connectible.v1.NotificationData', '9': 0, '10': 'notification'},
    {'1': 'clipboard', '3': 4, '4': 1, '5': 11, '6': '.connectible.v1.ClipboardHistoryEntry', '9': 0, '10': 'clipboard'},
    {'1': 'transfer_progress', '3': 5, '4': 1, '5': 11, '6': '.connectible.v1.TransferProgress', '9': 0, '10': 'transferProgress'},
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `LocalEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localEventDescriptor = $convert.base64Decode(
    'CgpMb2NhbEV2ZW50ElkKEXBhaXJpbmdfcmVxdWVzdGVkGAEgASgLMiouY29ubmVjdGlibGUudj'
    'EuUGFpcmluZ1JlcXVlc3RlZExvY2FsRXZlbnRIAFIQcGFpcmluZ1JlcXVlc3RlZBI5CgdiYXR0'
    'ZXJ5GAIgASgLMh0uY29ubmVjdGlibGUudjEuQmF0dGVyeVN0YXR1c0gAUgdiYXR0ZXJ5EkYKDG'
    '5vdGlmaWNhdGlvbhgDIAEoCzIgLmNvbm5lY3RpYmxlLnYxLk5vdGlmaWNhdGlvbkRhdGFIAFIM'
    'bm90aWZpY2F0aW9uEkUKCWNsaXBib2FyZBgEIAEoCzIlLmNvbm5lY3RpYmxlLnYxLkNsaXBib2'
    'FyZEhpc3RvcnlFbnRyeUgAUgljbGlwYm9hcmQSTwoRdHJhbnNmZXJfcHJvZ3Jlc3MYBSABKAsy'
    'IC5jb25uZWN0aWJsZS52MS5UcmFuc2ZlclByb2dyZXNzSABSEHRyYW5zZmVyUHJvZ3Jlc3NCBw'
    'oFZXZlbnQ=');

@$core.Deprecated('Use getLocalStateRequestDescriptor instead')
const GetLocalStateRequest$json = {
  '1': 'GetLocalStateRequest',
};

/// Descriptor for `GetLocalStateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLocalStateRequestDescriptor = $convert.base64Decode(
    'ChRHZXRMb2NhbFN0YXRlUmVxdWVzdA==');

@$core.Deprecated('Use nearbyDeviceDescriptor instead')
const NearbyDevice$json = {
  '1': 'NearbyDevice',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'device_name', '3': 2, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'platform', '3': 3, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'addr', '3': 4, '4': 1, '5': 9, '10': 'addr'},
    {'1': 'port', '3': 5, '4': 1, '5': 13, '10': 'port'},
    {'1': 'protocol_version', '3': 6, '4': 1, '5': 13, '10': 'protocolVersion'},
  ],
};

/// Descriptor for `NearbyDevice`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nearbyDeviceDescriptor = $convert.base64Decode(
    'CgxOZWFyYnlEZXZpY2USGwoJZGV2aWNlX2lkGAEgASgJUghkZXZpY2VJZBIfCgtkZXZpY2Vfbm'
    'FtZRgCIAEoCVIKZGV2aWNlTmFtZRIaCghwbGF0Zm9ybRgDIAEoCVIIcGxhdGZvcm0SEgoEYWRk'
    'chgEIAEoCVIEYWRkchISCgRwb3J0GAUgASgNUgRwb3J0EikKEHByb3RvY29sX3ZlcnNpb24YBi'
    'ABKA1SD3Byb3RvY29sVmVyc2lvbg==');

@$core.Deprecated('Use getLocalStateResponseDescriptor instead')
const GetLocalStateResponse$json = {
  '1': 'GetLocalStateResponse',
  '2': [
    {'1': 'local_identity', '3': 1, '4': 1, '5': 11, '6': '.connectible.v1.Identity', '10': 'localIdentity'},
    {'1': 'capabilities', '3': 2, '4': 3, '5': 9, '10': 'capabilities'},
    {'1': 'clipboard_history', '3': 3, '4': 3, '5': 11, '6': '.connectible.v1.ClipboardHistoryEntry', '10': 'clipboardHistory'},
    {'1': 'latest_battery', '3': 4, '4': 1, '5': 11, '6': '.connectible.v1.BatteryStatus', '10': 'latestBattery'},
    {'1': 'notifications', '3': 5, '4': 3, '5': 11, '6': '.connectible.v1.NotificationData', '10': 'notifications'},
    {'1': 'nearby_devices', '3': 6, '4': 3, '5': 11, '6': '.connectible.v1.NearbyDevice', '10': 'nearbyDevices'},
    {'1': 'remote_input_enabled', '3': 7, '4': 1, '5': 8, '10': 'remoteInputEnabled'},
    {'1': 'clipboard_sync_enabled', '3': 8, '4': 1, '5': 8, '10': 'clipboardSyncEnabled'},
  ],
};

/// Descriptor for `GetLocalStateResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLocalStateResponseDescriptor = $convert.base64Decode(
    'ChVHZXRMb2NhbFN0YXRlUmVzcG9uc2USPwoObG9jYWxfaWRlbnRpdHkYASABKAsyGC5jb25uZW'
    'N0aWJsZS52MS5JZGVudGl0eVINbG9jYWxJZGVudGl0eRIiCgxjYXBhYmlsaXRpZXMYAiADKAlS'
    'DGNhcGFiaWxpdGllcxJSChFjbGlwYm9hcmRfaGlzdG9yeRgDIAMoCzIlLmNvbm5lY3RpYmxlLn'
    'YxLkNsaXBib2FyZEhpc3RvcnlFbnRyeVIQY2xpcGJvYXJkSGlzdG9yeRJECg5sYXRlc3RfYmF0'
    'dGVyeRgEIAEoCzIdLmNvbm5lY3RpYmxlLnYxLkJhdHRlcnlTdGF0dXNSDWxhdGVzdEJhdHRlcn'
    'kSRgoNbm90aWZpY2F0aW9ucxgFIAMoCzIgLmNvbm5lY3RpYmxlLnYxLk5vdGlmaWNhdGlvbkRh'
    'dGFSDW5vdGlmaWNhdGlvbnMSQwoObmVhcmJ5X2RldmljZXMYBiADKAsyHC5jb25uZWN0aWJsZS'
    '52MS5OZWFyYnlEZXZpY2VSDW5lYXJieURldmljZXMSMAoUcmVtb3RlX2lucHV0X2VuYWJsZWQY'
    'ByABKAhSEnJlbW90ZUlucHV0RW5hYmxlZBI0ChZjbGlwYm9hcmRfc3luY19lbmFibGVkGAggAS'
    'gIUhRjbGlwYm9hcmRTeW5jRW5hYmxlZA==');

@$core.Deprecated('Use setRemoteInputEnabledRequestDescriptor instead')
const SetRemoteInputEnabledRequest$json = {
  '1': 'SetRemoteInputEnabledRequest',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetRemoteInputEnabledRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setRemoteInputEnabledRequestDescriptor = $convert.base64Decode(
    'ChxTZXRSZW1vdGVJbnB1dEVuYWJsZWRSZXF1ZXN0EhgKB2VuYWJsZWQYASABKAhSB2VuYWJsZW'
    'Q=');

@$core.Deprecated('Use setRemoteInputEnabledResponseDescriptor instead')
const SetRemoteInputEnabledResponse$json = {
  '1': 'SetRemoteInputEnabledResponse',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetRemoteInputEnabledResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setRemoteInputEnabledResponseDescriptor = $convert.base64Decode(
    'Ch1TZXRSZW1vdGVJbnB1dEVuYWJsZWRSZXNwb25zZRIYCgdlbmFibGVkGAEgASgIUgdlbmFibG'
    'Vk');

@$core.Deprecated('Use setClipboardSyncEnabledRequestDescriptor instead')
const SetClipboardSyncEnabledRequest$json = {
  '1': 'SetClipboardSyncEnabledRequest',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetClipboardSyncEnabledRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setClipboardSyncEnabledRequestDescriptor = $convert.base64Decode(
    'Ch5TZXRDbGlwYm9hcmRTeW5jRW5hYmxlZFJlcXVlc3QSGAoHZW5hYmxlZBgBIAEoCFIHZW5hYm'
    'xlZA==');

@$core.Deprecated('Use setClipboardSyncEnabledResponseDescriptor instead')
const SetClipboardSyncEnabledResponse$json = {
  '1': 'SetClipboardSyncEnabledResponse',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetClipboardSyncEnabledResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setClipboardSyncEnabledResponseDescriptor = $convert.base64Decode(
    'Ch9TZXRDbGlwYm9hcmRTeW5jRW5hYmxlZFJlc3BvbnNlEhgKB2VuYWJsZWQYASABKAhSB2VuYW'
    'JsZWQ=');

@$core.Deprecated('Use getPinnedFingerprintRequestDescriptor instead')
const GetPinnedFingerprintRequest$json = {
  '1': 'GetPinnedFingerprintRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `GetPinnedFingerprintRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPinnedFingerprintRequestDescriptor = $convert.base64Decode(
    'ChtHZXRQaW5uZWRGaW5nZXJwcmludFJlcXVlc3QSGwoJZGV2aWNlX2lkGAEgASgJUghkZXZpY2'
    'VJZA==');

@$core.Deprecated('Use getPinnedFingerprintResponseDescriptor instead')
const GetPinnedFingerprintResponse$json = {
  '1': 'GetPinnedFingerprintResponse',
  '2': [
    {'1': 'fingerprint', '3': 1, '4': 1, '5': 9, '10': 'fingerprint'},
  ],
};

/// Descriptor for `GetPinnedFingerprintResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPinnedFingerprintResponseDescriptor = $convert.base64Decode(
    'ChxHZXRQaW5uZWRGaW5nZXJwcmludFJlc3BvbnNlEiAKC2ZpbmdlcnByaW50GAEgASgJUgtmaW'
    '5nZXJwcmludA==');

@$core.Deprecated('Use recordFingerprintRequestDescriptor instead')
const RecordFingerprintRequest$json = {
  '1': 'RecordFingerprintRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'fingerprint', '3': 2, '4': 1, '5': 9, '10': 'fingerprint'},
  ],
};

/// Descriptor for `RecordFingerprintRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordFingerprintRequestDescriptor = $convert.base64Decode(
    'ChhSZWNvcmRGaW5nZXJwcmludFJlcXVlc3QSGwoJZGV2aWNlX2lkGAEgASgJUghkZXZpY2VJZB'
    'IgCgtmaW5nZXJwcmludBgCIAEoCVILZmluZ2VycHJpbnQ=');

@$core.Deprecated('Use recordFingerprintResponseDescriptor instead')
const RecordFingerprintResponse$json = {
  '1': 'RecordFingerprintResponse',
  '2': [
    {'1': 'recorded', '3': 1, '4': 1, '5': 8, '10': 'recorded'},
  ],
};

/// Descriptor for `RecordFingerprintResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordFingerprintResponseDescriptor = $convert.base64Decode(
    'ChlSZWNvcmRGaW5nZXJwcmludFJlc3BvbnNlEhoKCHJlY29yZGVkGAEgASgIUghyZWNvcmRlZA'
    '==');

@$core.Deprecated('Use runDiagnosticsRequestDescriptor instead')
const RunDiagnosticsRequest$json = {
  '1': 'RunDiagnosticsRequest',
  '2': [
    {'1': 'check_id', '3': 1, '4': 1, '5': 9, '10': 'checkId'},
  ],
};

/// Descriptor for `RunDiagnosticsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List runDiagnosticsRequestDescriptor = $convert.base64Decode(
    'ChVSdW5EaWFnbm9zdGljc1JlcXVlc3QSGQoIY2hlY2tfaWQYASABKAlSB2NoZWNrSWQ=');

@$core.Deprecated('Use diagnosticCheckDescriptor instead')
const DiagnosticCheck$json = {
  '1': 'DiagnosticCheck',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'category', '3': 3, '4': 1, '5': 9, '10': 'category'},
    {'1': 'status', '3': 4, '4': 1, '5': 9, '10': 'status'},
    {'1': 'summary', '3': 5, '4': 1, '5': 9, '10': 'summary'},
    {'1': 'detail', '3': 6, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'remediation', '3': 7, '4': 1, '5': 9, '10': 'remediation'},
    {'1': 'data', '3': 8, '4': 3, '5': 11, '6': '.connectible.v1.DiagnosticCheck.DataEntry', '10': 'data'},
  ],
  '3': [DiagnosticCheck_DataEntry$json],
};

@$core.Deprecated('Use diagnosticCheckDescriptor instead')
const DiagnosticCheck_DataEntry$json = {
  '1': 'DataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `DiagnosticCheck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diagnosticCheckDescriptor = $convert.base64Decode(
    'Cg9EaWFnbm9zdGljQ2hlY2sSDgoCaWQYASABKAlSAmlkEhQKBXRpdGxlGAIgASgJUgV0aXRsZR'
    'IaCghjYXRlZ29yeRgDIAEoCVIIY2F0ZWdvcnkSFgoGc3RhdHVzGAQgASgJUgZzdGF0dXMSGAoH'
    'c3VtbWFyeRgFIAEoCVIHc3VtbWFyeRIWCgZkZXRhaWwYBiABKAlSBmRldGFpbBIgCgtyZW1lZG'
    'lhdGlvbhgHIAEoCVILcmVtZWRpYXRpb24SPQoEZGF0YRgIIAMoCzIpLmNvbm5lY3RpYmxlLnYx'
    'LkRpYWdub3N0aWNDaGVjay5EYXRhRW50cnlSBGRhdGEaNwoJRGF0YUVudHJ5EhAKA2tleRgBIA'
    'EoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use runDiagnosticsResponseDescriptor instead')
const RunDiagnosticsResponse$json = {
  '1': 'RunDiagnosticsResponse',
  '2': [
    {'1': 'checks', '3': 1, '4': 3, '5': 11, '6': '.connectible.v1.DiagnosticCheck', '10': 'checks'},
    {'1': 'worst', '3': 2, '4': 1, '5': 9, '10': 'worst'},
  ],
};

/// Descriptor for `RunDiagnosticsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List runDiagnosticsResponseDescriptor = $convert.base64Decode(
    'ChZSdW5EaWFnbm9zdGljc1Jlc3BvbnNlEjcKBmNoZWNrcxgBIAMoCzIfLmNvbm5lY3RpYmxlLn'
    'YxLkRpYWdub3N0aWNDaGVja1IGY2hlY2tzEhQKBXdvcnN0GAIgASgJUgV3b3JzdA==');

