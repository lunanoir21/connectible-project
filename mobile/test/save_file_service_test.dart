import 'package:connectible_mobile/src/services/save_file_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// T-X6: the Dart half of the "Save to..." streaming bridge. The native
/// side (SaveFilePlugin.kt) owns the picker and the fixed-buffer copy;
/// these tests pin the channel contract the Dart wrapper must satisfy --
/// method name, argument shape, and how each native resolution (true /
/// false / error / missing) maps to a [SaveFileOutcome]. No file bytes
/// ever cross this channel, which is the whole point of the redesign.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = PlatformSaveFileService();

  void mockChannel(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saveFileChannel, handler);
  }

  setUp(() {
    // The Android branch is the one backed by the platform channel.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saveFileChannel, null);
  });

  test('passes only source path and file name to the native saveTo call',
      () async {
    MethodCall? seen;
    mockChannel((call) async {
      seen = call;
      return true;
    });

    final outcome = await service.saveAs(
        sourcePath: '/data/received/a.bin', fileName: 'a.bin');

    expect(outcome, SaveFileOutcome.saved);
    expect(seen!.method, 'saveTo');
    expect(seen!.arguments, {
      'sourcePath': '/data/received/a.bin',
      'fileName': 'a.bin',
    });
  });

  test('native false (user canceled the picker) maps to canceled', () async {
    mockChannel((call) async => false);
    expect(await service.saveAs(sourcePath: '/x', fileName: 'x'),
        SaveFileOutcome.canceled);
  });

  test('a native error maps to failed, not a crash', () async {
    mockChannel(
        (call) async => throw PlatformException(code: 'copy_failed'));
    expect(await service.saveAs(sourcePath: '/x', fileName: 'x'),
        SaveFileOutcome.failed);
  });

  test('a missing channel implementation maps to failed', () async {
    // No handler mocked at all -> MissingPluginException path.
    expect(await service.saveAs(sourcePath: '/x', fileName: 'x'),
        SaveFileOutcome.failed);
  });
}
