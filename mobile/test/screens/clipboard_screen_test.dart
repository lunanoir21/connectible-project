import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/screens/clipboard_screen.dart';
import 'package:connectible_mobile/src/state/clipboard_model.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_scaffold.dart';

/// Minimal [SyncConnection] test double that just records what
/// [ClipboardModel] pushes onto it, instead of needing a real network
/// connection (T-905).
class _FakeConnection implements SyncConnection {
  @override
  bool connected = true;

  @override
  String? get activePeerId => 'peer-1';

  final List<pb.SyncFrame> sent = [];

  @override
  void sendFrame(pb.SyncFrame frame) => sent.add(frame);

  @override
  pb.ConnectibleClient? get uploadClient => null;

  @override
  pb.Identity get localIdentity => pb.Identity(deviceId: 'this-device');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  /// Installs an in-memory mock for the OS clipboard platform channel and
  /// returns its backing store. Without this, `Clipboard.setData`/`getData`
  /// hit the real (unmocked) `SystemChannels.platform` MethodChannel and
  /// hang forever in the test binding.
  Map<String, Object?> mockClipboard() {
    final store = <String, Object?>{};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        store['text'] = (call.arguments as Map)['text'];
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': store['text']};
      }
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return store;
  }

  Future<DeviceListModel> buildDeviceList() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return DeviceListModel(prefs,
        deviceName: 'Test Phone', pairableEnabled: false);
  }

  PairingModel buildPairing(DeviceListModel deviceList) => PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        pairableEnabled: false,
      );

  testWidgets('shows the empty state and a disabled Send button when idle',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    final clipboard = ClipboardModel(connection: _FakeConnection());

    await tester.pumpWidget(wrapScreen(
      const ClipboardScreen(),
      providers: [
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<ClipboardModel>.value(value: clipboard),
      ],
    ));

    expect(find.text('Nothing copied yet'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'Send should be disabled while not connected');

    // Dispose synchronously here, not via addTearDown: ClipboardModel
    // owns a real Timer.periodic (T-304 background poll), and
    // addTearDown callbacks run *after* Flutter's own pending-timer
    // invariant check at the end of this test body, which is too late
    // to satisfy it.
    await tester.pumpWidget(const SizedBox.shrink());
    clipboard.dispose();
    pairing.dispose();
    deviceList.dispose();
  });

  testWidgets(
      'renders clipboard history entries with local/remote source labels',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList)..connected = true;
    final clipboard = ClipboardModel(connection: _FakeConnection())
      ..clipboard = const [
        ClipboardEntry(
            content: 'hello local', capturedAtMs: 2, source: 'local'),
        ClipboardEntry(
            content: 'hello remote', capturedAtMs: 1, source: 'Desk'),
      ];

    await tester.pumpWidget(wrapScreen(
      const ClipboardScreen(),
      providers: [
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<ClipboardModel>.value(value: clipboard),
      ],
    ));

    expect(find.text('hello local'), findsOneWidget);
    expect(find.text('hello remote'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Desk'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull,
        reason: 'Send should be enabled while connected');

    // See the first test's comment: dispose synchronously, not via
    // addTearDown, because of ClipboardModel's real Timer.periodic.
    await tester.pumpWidget(const SizedBox.shrink());
    clipboard.dispose();
    pairing.dispose();
    deviceList.dispose();
  });

  testWidgets('tapping Send pushes the current OS clipboard as a new entry',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList)..connected = true;
    final connection = _FakeConnection();
    // Hour-long poll interval so the background OS-clipboard Timer.periodic
    // (T-304) can never fire mid-test; a default 2s interval would keep the
    // pump loop below from ever quiescing (the T-E10 hang).
    final clipboard = ClipboardModel(
      connection: connection,
      pollInterval: const Duration(hours: 1),
    );

    mockClipboard();
    await Clipboard.setData(const ClipboardData(text: 'copied text'));

    await tester.pumpWidget(wrapScreen(
      const ClipboardScreen(),
      providers: [
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<ClipboardModel>.value(value: clipboard),
      ],
    ));

    await tester.tap(find.byType(FilledButton));
    // Bounded pump instead of pumpAndSettle: sendClipboard is async, so a
    // couple of frames flush the tap handler's future and the resulting
    // notifyListeners() rebuild without waiting on the periodic timer.
    await tester.pump();
    await tester.pump();

    expect(clipboard.clipboard, isNotEmpty);
    expect(clipboard.clipboard.first.content, 'copied text');
    expect(clipboard.clipboard.first.source, 'local');
    expect(connection.sent, hasLength(1));
    expect(connection.sent.single.clipboard.content, 'copied text'.codeUnits);

    // See the first test's comment: dispose synchronously, not via
    // addTearDown, because of ClipboardModel's real Timer.periodic.
    await tester.pumpWidget(const SizedBox.shrink());
    clipboard.dispose();
    pairing.dispose();
    deviceList.dispose();
  });
}
