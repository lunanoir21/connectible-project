import 'package:connectible_mobile/src/services/mdns_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// T-X20: the Wi-Fi multicast lock is held for the duration of mDNS
/// discovery. These exercise the Dart side against a mocked
/// `connectible/multicast` channel -- the real WifiManager lock can only
/// be verified on a physical Android device (flagged for the owner).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    // acquireMulticastLock() early-returns off Android; pretend we're on it.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(multicastLockChannel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(multicastLockChannel, null);
  });

  test('acquire/release invoke the native channel once each, idempotently',
      () async {
    final mdns = MdnsService();

    await mdns.acquireMulticastLock();
    await mdns.acquireMulticastLock(); // held -> no second native acquire
    expect(calls, ['acquire']);

    await mdns.releaseMulticastLock();
    await mdns.releaseMulticastLock(); // not held -> no second native release
    expect(calls, ['acquire', 'release']);

    // A fresh acquire after release works again (lock re-taken next sweep).
    await mdns.acquireMulticastLock();
    expect(calls, ['acquire', 'release', 'acquire']);
  });

  test('release without a prior acquire is a no-op', () async {
    final mdns = MdnsService();
    await mdns.releaseMulticastLock();
    expect(calls, isEmpty);
  });

  test('a native acquire failure is swallowed, not thrown (best-effort aid)',
      () async {
    messenger.setMockMethodCallHandler(multicastLockChannel, (call) async {
      throw PlatformException(code: 'acquire_failed', message: 'no wifi');
    });
    final mdns = MdnsService();
    // Must not throw -- a failed lock must never break discovery itself.
    await mdns.acquireMulticastLock();
    // Held stayed false, so a later release is a clean no-op too.
    await mdns.releaseMulticastLock();
  });
}
