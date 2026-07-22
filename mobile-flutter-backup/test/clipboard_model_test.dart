import 'dart:convert';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/state/clipboard_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records outbound frames; connected by default.
class _FakeConnection implements SyncConnection {
  @override
  bool connected = true;
  @override
  String? get activePeerId => 'peer-1';
  @override
  pb.ConnectibleClient? get uploadClient => null;
  @override
  pb.Identity get localIdentity => pb.Identity(deviceId: 'this-device');
  final List<pb.SyncFrame> sent = [];
  @override
  void sendFrame(pb.SyncFrame frame) => sent.add(frame);

  List<pb.ClipboardData> get clipboardFrames => sent
      .where((f) => f.whichPayload() == pb.SyncFrame_Payload.clipboard)
      .map((f) => f.clipboard)
      .toList();
}

pb.ClipboardData _inbound(String text) {
  final bytes = utf8.encode(text);
  return pb.ClipboardData(
    mimeType: 'text/plain',
    content: bytes,
    capturedAtMs: Int64(1000),
    contentHash: ClipboardEchoGuard.hashContent(text),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardModel auto-apply gating (T-B11)', () {
    // Capture what the model writes to the OS clipboard via the platform
    // channel, without a real device.
    final applied = <String>[];
    setUp(() {
      applied.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          applied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('auto-apply on writes inbound content to the OS clipboard', () async {
      final model = ClipboardModel(
        connection: _FakeConnection(),
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(model.dispose);

      model.handleInbound(_inbound('from peer'));
      await Future<void>.delayed(Duration.zero);

      expect(applied, ['from peer']);
      // It also lands in history regardless.
      expect(model.clipboard.first.content, 'from peer');
    });

    test('auto-apply off keeps inbound in history but does not write to the '
        'OS clipboard', () async {
      final model = ClipboardModel(
        connection: _FakeConnection(),
        pollInterval: const Duration(hours: 1),
        autoApply: false,
      );
      addTearDown(model.dispose);

      model.handleInbound(_inbound('from peer'));
      await Future<void>.delayed(Duration.zero);

      expect(applied, isEmpty);
      expect(model.clipboard.first.content, 'from peer');
    });

    test('setAutoApply flips the behavior live', () async {
      final model = ClipboardModel(
        connection: _FakeConnection(),
        pollInterval: const Duration(hours: 1),
        autoApply: false,
      );
      addTearDown(model.dispose);

      model.setAutoApply(true);
      model.handleInbound(_inbound('now applied'));
      await Future<void>.delayed(Duration.zero);

      expect(applied, ['now applied']);
    });
  });

  group('ClipboardEchoGuard', () {
    test('first observation of content is a new local change', () {
      final guard = ClipboardEchoGuard();
      expect(guard.observeLocalChange('hello'), isTrue);
    });

    test('repeated poll of unchanged content is not resent', () {
      final guard = ClipboardEchoGuard();
      expect(guard.observeLocalChange('hello'), isTrue);
      expect(guard.observeLocalChange('hello'), isFalse);
      expect(guard.observeLocalChange('hello'), isFalse);
    });

    test('content applied from a peer is not echoed back as local', () {
      final guard = ClipboardEchoGuard();
      final hash = ClipboardEchoGuard.hashContent('from peer');

      guard.recordApplied(hash);

      // Simulate the poll loop reading the OS clipboard back right after
      // the inbound frame was auto-applied -- this must not be reported
      // as a new local change (no echo loop back to the sender).
      expect(guard.observeLocalChange('from peer'), isFalse);
    });

    test('genuinely new local content after an applied update is detected',
        () {
      final guard = ClipboardEchoGuard();
      guard.recordApplied(ClipboardEchoGuard.hashContent('from peer'));
      expect(guard.observeLocalChange('from peer'), isFalse);

      // The user now copies something new locally -- must be detected.
      expect(guard.observeLocalChange('something new'), isTrue);
      // And immediately polling the same content again must not re-fire.
      expect(guard.observeLocalChange('something new'), isFalse);
    });

    test('applying a second inbound update updates the suppressed hash', () {
      final guard = ClipboardEchoGuard();
      guard.recordApplied(ClipboardEchoGuard.hashContent('first'));
      expect(guard.observeLocalChange('first'), isFalse);

      guard.recordApplied(ClipboardEchoGuard.hashContent('second'));
      // The old applied hash ("first") is no longer the suppression
      // target; only the latest applied content is suppressed.
      expect(guard.observeLocalChange('second'), isFalse);
    });

    test('lastLocalHash and lastAppliedHash reflect the latest observation',
        () {
      final guard = ClipboardEchoGuard();
      guard.observeLocalChange('a');
      expect(guard.lastLocalHash, ClipboardEchoGuard.hashContent('a'));
      expect(guard.lastAppliedHash, isNull);

      guard.recordApplied(ClipboardEchoGuard.hashContent('b'));
      expect(guard.lastAppliedHash, ClipboardEchoGuard.hashContent('b'));
      expect(guard.lastLocalHash, ClipboardEchoGuard.hashContent('b'));
    });
  });
}
