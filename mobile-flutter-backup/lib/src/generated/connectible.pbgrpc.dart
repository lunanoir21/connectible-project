//
//  Generated code. Do not modify.
//  source: connectible.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'connectible.pb.dart' as $0;

export 'connectible.pb.dart';

@$pb.GrpcServiceName('connectible.v1.Connectible')
class ConnectibleClient extends $grpc.Client {
  static final _$syncStream = $grpc.ClientMethod<$0.SyncFrame, $0.SyncFrame>(
      '/connectible.v1.Connectible/SyncStream',
      ($0.SyncFrame value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.SyncFrame.fromBuffer(value));
  static final _$prepareUpload = $grpc.ClientMethod<$0.PrepareUploadRequest, $0.PrepareUploadResponse>(
      '/connectible.v1.Connectible/PrepareUpload',
      ($0.PrepareUploadRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.PrepareUploadResponse.fromBuffer(value));
  static final _$uploadFile = $grpc.ClientMethod<$0.UploadFilePart, $0.UploadFileResult>(
      '/connectible.v1.Connectible/UploadFile',
      ($0.UploadFilePart value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.UploadFileResult.fromBuffer(value));
  static final _$pair = $grpc.ClientMethod<$0.PairRequest, $0.PairResponse>(
      '/connectible.v1.Connectible/Pair',
      ($0.PairRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.PairResponse.fromBuffer(value));
  static final _$confirmPin = $grpc.ClientMethod<$0.ConfirmPinRequest, $0.ConfirmPinResponse>(
      '/connectible.v1.Connectible/ConfirmPin',
      ($0.ConfirmPinRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.ConfirmPinResponse.fromBuffer(value));
  static final _$listDevices = $grpc.ClientMethod<$0.ListDevicesRequest, $0.ListDevicesResponse>(
      '/connectible.v1.Connectible/ListDevices',
      ($0.ListDevicesRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.ListDevicesResponse.fromBuffer(value));
  static final _$disconnectDevice = $grpc.ClientMethod<$0.DisconnectDeviceRequest, $0.DisconnectDeviceResponse>(
      '/connectible.v1.Connectible/DisconnectDevice',
      ($0.DisconnectDeviceRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.DisconnectDeviceResponse.fromBuffer(value));
  static final _$forgetDevice = $grpc.ClientMethod<$0.ForgetDeviceRequest, $0.ForgetDeviceResponse>(
      '/connectible.v1.Connectible/ForgetDevice',
      ($0.ForgetDeviceRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.ForgetDeviceResponse.fromBuffer(value));
  static final _$ping = $grpc.ClientMethod<$0.PingRequest, $0.PongRequest>(
      '/connectible.v1.Connectible/Ping',
      ($0.PingRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.PongRequest.fromBuffer(value));
  static final _$subscribeLocalEvents = $grpc.ClientMethod<$0.LocalEventsRequest, $0.LocalEvent>(
      '/connectible.v1.Connectible/SubscribeLocalEvents',
      ($0.LocalEventsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.LocalEvent.fromBuffer(value));
  static final _$getLocalState = $grpc.ClientMethod<$0.GetLocalStateRequest, $0.GetLocalStateResponse>(
      '/connectible.v1.Connectible/GetLocalState',
      ($0.GetLocalStateRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.GetLocalStateResponse.fromBuffer(value));
  static final _$setRemoteInputEnabled = $grpc.ClientMethod<$0.SetRemoteInputEnabledRequest, $0.SetRemoteInputEnabledResponse>(
      '/connectible.v1.Connectible/SetRemoteInputEnabled',
      ($0.SetRemoteInputEnabledRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.SetRemoteInputEnabledResponse.fromBuffer(value));
  static final _$setClipboardSyncEnabled = $grpc.ClientMethod<$0.SetClipboardSyncEnabledRequest, $0.SetClipboardSyncEnabledResponse>(
      '/connectible.v1.Connectible/SetClipboardSyncEnabled',
      ($0.SetClipboardSyncEnabledRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.SetClipboardSyncEnabledResponse.fromBuffer(value));
  static final _$getPinnedFingerprint = $grpc.ClientMethod<$0.GetPinnedFingerprintRequest, $0.GetPinnedFingerprintResponse>(
      '/connectible.v1.Connectible/GetPinnedFingerprint',
      ($0.GetPinnedFingerprintRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.GetPinnedFingerprintResponse.fromBuffer(value));
  static final _$recordFingerprint = $grpc.ClientMethod<$0.RecordFingerprintRequest, $0.RecordFingerprintResponse>(
      '/connectible.v1.Connectible/RecordFingerprint',
      ($0.RecordFingerprintRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.RecordFingerprintResponse.fromBuffer(value));
  static final _$runDiagnostics = $grpc.ClientMethod<$0.RunDiagnosticsRequest, $0.RunDiagnosticsResponse>(
      '/connectible.v1.Connectible/RunDiagnostics',
      ($0.RunDiagnosticsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.RunDiagnosticsResponse.fromBuffer(value));

  ConnectibleClient($grpc.ClientChannel channel,
      {$grpc.CallOptions? options,
      $core.Iterable<$grpc.ClientInterceptor>? interceptors})
      : super(channel, options: options,
        interceptors: interceptors);

  $grpc.ResponseStream<$0.SyncFrame> syncStream($async.Stream<$0.SyncFrame> request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$syncStream, request, options: options);
  }

  $grpc.ResponseFuture<$0.PrepareUploadResponse> prepareUpload($0.PrepareUploadRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$prepareUpload, request, options: options);
  }

  $grpc.ResponseFuture<$0.UploadFileResult> uploadFile($async.Stream<$0.UploadFilePart> request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$uploadFile, request, options: options).single;
  }

  $grpc.ResponseFuture<$0.PairResponse> pair($0.PairRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$pair, request, options: options);
  }

  $grpc.ResponseFuture<$0.ConfirmPinResponse> confirmPin($0.ConfirmPinRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$confirmPin, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListDevicesResponse> listDevices($0.ListDevicesRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$listDevices, request, options: options);
  }

  $grpc.ResponseFuture<$0.DisconnectDeviceResponse> disconnectDevice($0.DisconnectDeviceRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$disconnectDevice, request, options: options);
  }

  $grpc.ResponseFuture<$0.ForgetDeviceResponse> forgetDevice($0.ForgetDeviceRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$forgetDevice, request, options: options);
  }

  $grpc.ResponseFuture<$0.PongRequest> ping($0.PingRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$ping, request, options: options);
  }

  $grpc.ResponseStream<$0.LocalEvent> subscribeLocalEvents($0.LocalEventsRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$subscribeLocalEvents, $async.Stream.fromIterable([request]), options: options);
  }

  $grpc.ResponseFuture<$0.GetLocalStateResponse> getLocalState($0.GetLocalStateRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getLocalState, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetRemoteInputEnabledResponse> setRemoteInputEnabled($0.SetRemoteInputEnabledRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$setRemoteInputEnabled, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetClipboardSyncEnabledResponse> setClipboardSyncEnabled($0.SetClipboardSyncEnabledRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$setClipboardSyncEnabled, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetPinnedFingerprintResponse> getPinnedFingerprint($0.GetPinnedFingerprintRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getPinnedFingerprint, request, options: options);
  }

  $grpc.ResponseFuture<$0.RecordFingerprintResponse> recordFingerprint($0.RecordFingerprintRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$recordFingerprint, request, options: options);
  }

  $grpc.ResponseFuture<$0.RunDiagnosticsResponse> runDiagnostics($0.RunDiagnosticsRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$runDiagnostics, request, options: options);
  }
}

@$pb.GrpcServiceName('connectible.v1.Connectible')
abstract class ConnectibleServiceBase extends $grpc.Service {
  $core.String get $name => 'connectible.v1.Connectible';

  ConnectibleServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SyncFrame, $0.SyncFrame>(
        'SyncStream',
        syncStream,
        true,
        true,
        ($core.List<$core.int> value) => $0.SyncFrame.fromBuffer(value),
        ($0.SyncFrame value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PrepareUploadRequest, $0.PrepareUploadResponse>(
        'PrepareUpload',
        prepareUpload_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PrepareUploadRequest.fromBuffer(value),
        ($0.PrepareUploadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UploadFilePart, $0.UploadFileResult>(
        'UploadFile',
        uploadFile,
        true,
        false,
        ($core.List<$core.int> value) => $0.UploadFilePart.fromBuffer(value),
        ($0.UploadFileResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PairRequest, $0.PairResponse>(
        'Pair',
        pair_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PairRequest.fromBuffer(value),
        ($0.PairResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ConfirmPinRequest, $0.ConfirmPinResponse>(
        'ConfirmPin',
        confirmPin_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ConfirmPinRequest.fromBuffer(value),
        ($0.ConfirmPinResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListDevicesRequest, $0.ListDevicesResponse>(
        'ListDevices',
        listDevices_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListDevicesRequest.fromBuffer(value),
        ($0.ListDevicesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DisconnectDeviceRequest, $0.DisconnectDeviceResponse>(
        'DisconnectDevice',
        disconnectDevice_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.DisconnectDeviceRequest.fromBuffer(value),
        ($0.DisconnectDeviceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ForgetDeviceRequest, $0.ForgetDeviceResponse>(
        'ForgetDevice',
        forgetDevice_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ForgetDeviceRequest.fromBuffer(value),
        ($0.ForgetDeviceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PingRequest, $0.PongRequest>(
        'Ping',
        ping_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PingRequest.fromBuffer(value),
        ($0.PongRequest value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LocalEventsRequest, $0.LocalEvent>(
        'SubscribeLocalEvents',
        subscribeLocalEvents_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.LocalEventsRequest.fromBuffer(value),
        ($0.LocalEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetLocalStateRequest, $0.GetLocalStateResponse>(
        'GetLocalState',
        getLocalState_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetLocalStateRequest.fromBuffer(value),
        ($0.GetLocalStateResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetRemoteInputEnabledRequest, $0.SetRemoteInputEnabledResponse>(
        'SetRemoteInputEnabled',
        setRemoteInputEnabled_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetRemoteInputEnabledRequest.fromBuffer(value),
        ($0.SetRemoteInputEnabledResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetClipboardSyncEnabledRequest, $0.SetClipboardSyncEnabledResponse>(
        'SetClipboardSyncEnabled',
        setClipboardSyncEnabled_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetClipboardSyncEnabledRequest.fromBuffer(value),
        ($0.SetClipboardSyncEnabledResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetPinnedFingerprintRequest, $0.GetPinnedFingerprintResponse>(
        'GetPinnedFingerprint',
        getPinnedFingerprint_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetPinnedFingerprintRequest.fromBuffer(value),
        ($0.GetPinnedFingerprintResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RecordFingerprintRequest, $0.RecordFingerprintResponse>(
        'RecordFingerprint',
        recordFingerprint_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.RecordFingerprintRequest.fromBuffer(value),
        ($0.RecordFingerprintResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RunDiagnosticsRequest, $0.RunDiagnosticsResponse>(
        'RunDiagnostics',
        runDiagnostics_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.RunDiagnosticsRequest.fromBuffer(value),
        ($0.RunDiagnosticsResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.PrepareUploadResponse> prepareUpload_Pre($grpc.ServiceCall call, $async.Future<$0.PrepareUploadRequest> request) async {
    return prepareUpload(call, await request);
  }

  $async.Future<$0.PairResponse> pair_Pre($grpc.ServiceCall call, $async.Future<$0.PairRequest> request) async {
    return pair(call, await request);
  }

  $async.Future<$0.ConfirmPinResponse> confirmPin_Pre($grpc.ServiceCall call, $async.Future<$0.ConfirmPinRequest> request) async {
    return confirmPin(call, await request);
  }

  $async.Future<$0.ListDevicesResponse> listDevices_Pre($grpc.ServiceCall call, $async.Future<$0.ListDevicesRequest> request) async {
    return listDevices(call, await request);
  }

  $async.Future<$0.DisconnectDeviceResponse> disconnectDevice_Pre($grpc.ServiceCall call, $async.Future<$0.DisconnectDeviceRequest> request) async {
    return disconnectDevice(call, await request);
  }

  $async.Future<$0.ForgetDeviceResponse> forgetDevice_Pre($grpc.ServiceCall call, $async.Future<$0.ForgetDeviceRequest> request) async {
    return forgetDevice(call, await request);
  }

  $async.Future<$0.PongRequest> ping_Pre($grpc.ServiceCall call, $async.Future<$0.PingRequest> request) async {
    return ping(call, await request);
  }

  $async.Stream<$0.LocalEvent> subscribeLocalEvents_Pre($grpc.ServiceCall call, $async.Future<$0.LocalEventsRequest> request) async* {
    yield* subscribeLocalEvents(call, await request);
  }

  $async.Future<$0.GetLocalStateResponse> getLocalState_Pre($grpc.ServiceCall call, $async.Future<$0.GetLocalStateRequest> request) async {
    return getLocalState(call, await request);
  }

  $async.Future<$0.SetRemoteInputEnabledResponse> setRemoteInputEnabled_Pre($grpc.ServiceCall call, $async.Future<$0.SetRemoteInputEnabledRequest> request) async {
    return setRemoteInputEnabled(call, await request);
  }

  $async.Future<$0.SetClipboardSyncEnabledResponse> setClipboardSyncEnabled_Pre($grpc.ServiceCall call, $async.Future<$0.SetClipboardSyncEnabledRequest> request) async {
    return setClipboardSyncEnabled(call, await request);
  }

  $async.Future<$0.GetPinnedFingerprintResponse> getPinnedFingerprint_Pre($grpc.ServiceCall call, $async.Future<$0.GetPinnedFingerprintRequest> request) async {
    return getPinnedFingerprint(call, await request);
  }

  $async.Future<$0.RecordFingerprintResponse> recordFingerprint_Pre($grpc.ServiceCall call, $async.Future<$0.RecordFingerprintRequest> request) async {
    return recordFingerprint(call, await request);
  }

  $async.Future<$0.RunDiagnosticsResponse> runDiagnostics_Pre($grpc.ServiceCall call, $async.Future<$0.RunDiagnosticsRequest> request) async {
    return runDiagnostics(call, await request);
  }

  $async.Stream<$0.SyncFrame> syncStream($grpc.ServiceCall call, $async.Stream<$0.SyncFrame> request);
  $async.Future<$0.PrepareUploadResponse> prepareUpload($grpc.ServiceCall call, $0.PrepareUploadRequest request);
  $async.Future<$0.UploadFileResult> uploadFile($grpc.ServiceCall call, $async.Stream<$0.UploadFilePart> request);
  $async.Future<$0.PairResponse> pair($grpc.ServiceCall call, $0.PairRequest request);
  $async.Future<$0.ConfirmPinResponse> confirmPin($grpc.ServiceCall call, $0.ConfirmPinRequest request);
  $async.Future<$0.ListDevicesResponse> listDevices($grpc.ServiceCall call, $0.ListDevicesRequest request);
  $async.Future<$0.DisconnectDeviceResponse> disconnectDevice($grpc.ServiceCall call, $0.DisconnectDeviceRequest request);
  $async.Future<$0.ForgetDeviceResponse> forgetDevice($grpc.ServiceCall call, $0.ForgetDeviceRequest request);
  $async.Future<$0.PongRequest> ping($grpc.ServiceCall call, $0.PingRequest request);
  $async.Stream<$0.LocalEvent> subscribeLocalEvents($grpc.ServiceCall call, $0.LocalEventsRequest request);
  $async.Future<$0.GetLocalStateResponse> getLocalState($grpc.ServiceCall call, $0.GetLocalStateRequest request);
  $async.Future<$0.SetRemoteInputEnabledResponse> setRemoteInputEnabled($grpc.ServiceCall call, $0.SetRemoteInputEnabledRequest request);
  $async.Future<$0.SetClipboardSyncEnabledResponse> setClipboardSyncEnabled($grpc.ServiceCall call, $0.SetClipboardSyncEnabledRequest request);
  $async.Future<$0.GetPinnedFingerprintResponse> getPinnedFingerprint($grpc.ServiceCall call, $0.GetPinnedFingerprintRequest request);
  $async.Future<$0.RecordFingerprintResponse> recordFingerprint($grpc.ServiceCall call, $0.RecordFingerprintRequest request);
  $async.Future<$0.RunDiagnosticsResponse> runDiagnostics($grpc.ServiceCall call, $0.RunDiagnosticsRequest request);
}
