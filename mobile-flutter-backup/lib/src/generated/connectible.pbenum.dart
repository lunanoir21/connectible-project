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

import 'package:protobuf/protobuf.dart' as $pb;

/// Platform the peer is running on. Used to adapt input injection and
/// clipboard backends (e.g. daemon picks ydotool vs wayland-client vs
/// mobile IME hooks).
class Platform extends $pb.ProtobufEnum {
  static const Platform PLATFORM_UNSPECIFIED = Platform._(0, _omitEnumNames ? '' : 'PLATFORM_UNSPECIFIED');
  static const Platform PLATFORM_LINUX_X11 = Platform._(1, _omitEnumNames ? '' : 'PLATFORM_LINUX_X11');
  static const Platform PLATFORM_LINUX_WAYLAND = Platform._(2, _omitEnumNames ? '' : 'PLATFORM_LINUX_WAYLAND');
  static const Platform PLATFORM_WINDOWS = Platform._(3, _omitEnumNames ? '' : 'PLATFORM_WINDOWS');
  static const Platform PLATFORM_MACOS = Platform._(4, _omitEnumNames ? '' : 'PLATFORM_MACOS');
  static const Platform PLATFORM_ANDROID = Platform._(5, _omitEnumNames ? '' : 'PLATFORM_ANDROID');
  static const Platform PLATFORM_IOS = Platform._(6, _omitEnumNames ? '' : 'PLATFORM_IOS');

  static const $core.List<Platform> values = <Platform> [
    PLATFORM_UNSPECIFIED,
    PLATFORM_LINUX_X11,
    PLATFORM_LINUX_WAYLAND,
    PLATFORM_WINDOWS,
    PLATFORM_MACOS,
    PLATFORM_ANDROID,
    PLATFORM_IOS,
  ];

  static final $core.Map<$core.int, Platform> _byValue = $pb.ProtobufEnum.initByValue(values);
  static Platform? valueOf($core.int value) => _byValue[value];

  const Platform._($core.int v, $core.String n) : super(v, n);
}

/// Coarse device role, purely informational for UI iconography.
class DeviceType extends $pb.ProtobufEnum {
  static const DeviceType DEVICE_TYPE_UNSPECIFIED = DeviceType._(0, _omitEnumNames ? '' : 'DEVICE_TYPE_UNSPECIFIED');
  static const DeviceType DEVICE_TYPE_DESKTOP = DeviceType._(1, _omitEnumNames ? '' : 'DEVICE_TYPE_DESKTOP');
  static const DeviceType DEVICE_TYPE_LAPTOP = DeviceType._(2, _omitEnumNames ? '' : 'DEVICE_TYPE_LAPTOP');
  static const DeviceType DEVICE_TYPE_PHONE = DeviceType._(3, _omitEnumNames ? '' : 'DEVICE_TYPE_PHONE');
  static const DeviceType DEVICE_TYPE_TABLET = DeviceType._(4, _omitEnumNames ? '' : 'DEVICE_TYPE_TABLET');

  static const $core.List<DeviceType> values = <DeviceType> [
    DEVICE_TYPE_UNSPECIFIED,
    DEVICE_TYPE_DESKTOP,
    DEVICE_TYPE_LAPTOP,
    DEVICE_TYPE_PHONE,
    DEVICE_TYPE_TABLET,
  ];

  static final $core.Map<$core.int, DeviceType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DeviceType? valueOf($core.int value) => _byValue[value];

  const DeviceType._($core.int v, $core.String n) : super(v, n);
}

/// Type of remote input event carried inside RemoteInputEvent.payload.
class InputEventType extends $pb.ProtobufEnum {
  static const InputEventType INPUT_EVENT_TYPE_UNSPECIFIED = InputEventType._(0, _omitEnumNames ? '' : 'INPUT_EVENT_TYPE_UNSPECIFIED');
  static const InputEventType INPUT_EVENT_TYPE_MOUSE_MOVE = InputEventType._(1, _omitEnumNames ? '' : 'INPUT_EVENT_TYPE_MOUSE_MOVE');
  static const InputEventType INPUT_EVENT_TYPE_MOUSE_BUTTON = InputEventType._(2, _omitEnumNames ? '' : 'INPUT_EVENT_TYPE_MOUSE_BUTTON');
  static const InputEventType INPUT_EVENT_TYPE_MOUSE_SCROLL = InputEventType._(3, _omitEnumNames ? '' : 'INPUT_EVENT_TYPE_MOUSE_SCROLL');
  static const InputEventType INPUT_EVENT_TYPE_KEY = InputEventType._(4, _omitEnumNames ? '' : 'INPUT_EVENT_TYPE_KEY');

  static const $core.List<InputEventType> values = <InputEventType> [
    INPUT_EVENT_TYPE_UNSPECIFIED,
    INPUT_EVENT_TYPE_MOUSE_MOVE,
    INPUT_EVENT_TYPE_MOUSE_BUTTON,
    INPUT_EVENT_TYPE_MOUSE_SCROLL,
    INPUT_EVENT_TYPE_KEY,
  ];

  static final $core.Map<$core.int, InputEventType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static InputEventType? valueOf($core.int value) => _byValue[value];

  const InputEventType._($core.int v, $core.String n) : super(v, n);
}

/// Mouse button identifiers, deliberately mirroring X11 button numbering
/// so the daemon's X11 backend needs no translation table.
class MouseButton extends $pb.ProtobufEnum {
  static const MouseButton MOUSE_BUTTON_UNSPECIFIED = MouseButton._(0, _omitEnumNames ? '' : 'MOUSE_BUTTON_UNSPECIFIED');
  static const MouseButton MOUSE_BUTTON_LEFT = MouseButton._(1, _omitEnumNames ? '' : 'MOUSE_BUTTON_LEFT');
  static const MouseButton MOUSE_BUTTON_MIDDLE = MouseButton._(2, _omitEnumNames ? '' : 'MOUSE_BUTTON_MIDDLE');
  static const MouseButton MOUSE_BUTTON_RIGHT = MouseButton._(3, _omitEnumNames ? '' : 'MOUSE_BUTTON_RIGHT');

  static const $core.List<MouseButton> values = <MouseButton> [
    MOUSE_BUTTON_UNSPECIFIED,
    MOUSE_BUTTON_LEFT,
    MOUSE_BUTTON_MIDDLE,
    MOUSE_BUTTON_RIGHT,
  ];

  static final $core.Map<$core.int, MouseButton> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MouseButton? valueOf($core.int value) => _byValue[value];

  const MouseButton._($core.int v, $core.String n) : super(v, n);
}

/// Standardized error codes so clients can branch on error type instead
/// of parsing human-readable message strings.
class ErrorCode extends $pb.ProtobufEnum {
  static const ErrorCode ERROR_CODE_UNSPECIFIED = ErrorCode._(0, _omitEnumNames ? '' : 'ERROR_CODE_UNSPECIFIED');
  static const ErrorCode ERROR_CODE_UNAUTHENTICATED = ErrorCode._(1, _omitEnumNames ? '' : 'ERROR_CODE_UNAUTHENTICATED');
  static const ErrorCode ERROR_CODE_PAIRING_REJECTED = ErrorCode._(2, _omitEnumNames ? '' : 'ERROR_CODE_PAIRING_REJECTED');
  static const ErrorCode ERROR_CODE_PAIRING_TIMEOUT = ErrorCode._(3, _omitEnumNames ? '' : 'ERROR_CODE_PAIRING_TIMEOUT');
  static const ErrorCode ERROR_CODE_DEVICE_NOT_FOUND = ErrorCode._(4, _omitEnumNames ? '' : 'ERROR_CODE_DEVICE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_FILE_TRANSFER_FAILED = ErrorCode._(5, _omitEnumNames ? '' : 'ERROR_CODE_FILE_TRANSFER_FAILED');
  static const ErrorCode ERROR_CODE_CHECKSUM_MISMATCH = ErrorCode._(6, _omitEnumNames ? '' : 'ERROR_CODE_CHECKSUM_MISMATCH');
  static const ErrorCode ERROR_CODE_UNSUPPORTED_PLATFORM = ErrorCode._(7, _omitEnumNames ? '' : 'ERROR_CODE_UNSUPPORTED_PLATFORM');
  static const ErrorCode ERROR_CODE_INTERNAL = ErrorCode._(8, _omitEnumNames ? '' : 'ERROR_CODE_INTERNAL');
  static const ErrorCode ERROR_CODE_PROTOCOL_VERSION_MISMATCH = ErrorCode._(9, _omitEnumNames ? '' : 'ERROR_CODE_PROTOCOL_VERSION_MISMATCH');
  static const ErrorCode ERROR_CODE_RATE_LIMITED = ErrorCode._(10, _omitEnumNames ? '' : 'ERROR_CODE_RATE_LIMITED');
  static const ErrorCode ERROR_CODE_FINGERPRINT_CHANGED = ErrorCode._(11, _omitEnumNames ? '' : 'ERROR_CODE_FINGERPRINT_CHANGED');

  static const $core.List<ErrorCode> values = <ErrorCode> [
    ERROR_CODE_UNSPECIFIED,
    ERROR_CODE_UNAUTHENTICATED,
    ERROR_CODE_PAIRING_REJECTED,
    ERROR_CODE_PAIRING_TIMEOUT,
    ERROR_CODE_DEVICE_NOT_FOUND,
    ERROR_CODE_FILE_TRANSFER_FAILED,
    ERROR_CODE_CHECKSUM_MISMATCH,
    ERROR_CODE_UNSUPPORTED_PLATFORM,
    ERROR_CODE_INTERNAL,
    ERROR_CODE_PROTOCOL_VERSION_MISMATCH,
    ERROR_CODE_RATE_LIMITED,
    ERROR_CODE_FINGERPRINT_CHANGED,
  ];

  static final $core.Map<$core.int, ErrorCode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ErrorCode? valueOf($core.int value) => _byValue[value];

  const ErrorCode._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
