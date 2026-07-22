import 'dart:async';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/screens/remote_input_screen.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DeviceListModel> buildDeviceList() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return DeviceListModel(prefs,
        deviceName: 'Test Phone', pairableEnabled: false);
  }

  PairingModel buildPairing(DeviceListModel deviceList) => PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        onFileTransferStart: (_) {},
        onFileChunk: (_) {},
        onFileChunkRequest: (_) {},
        pairableEnabled: false,
      );

  testWidgets('shows the empty state hint when no device is connected',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const RemoteInputScreen(),
      providers: [ChangeNotifierProvider<PairingModel>.value(value: pairing)],
    ));

    expect(find.text('Remote control'), findsOneWidget);
    expect(find.text('Pair a computer to control it from here.'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'left-click button sends a press+release mouse event over the active '
      'session', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    // Drive the responder path directly (T-905): onInboundSyncStream is
    // the same ServerDelegate entry point a real peer's SyncStream RPC
    // would hit, and it hands back the outbound stream PairingModel
    // pushes frames onto via sendFrame -- letting the test observe every
    // RemoteInputEvent the screen emits without a real network socket.
    final inbound = StreamController<pb.SyncFrame>();
    final sentFrames = <pb.SyncFrame>[];
    final sub = pairing.onInboundSyncStream(inbound.stream).listen(sentFrames.add);
    addTearDown(() async {
      // inbound.close() schedules its onDone (-> PairingModel's
      // _closeInboundSession -> notifyListeners) as a microtask; awaiting
      // the close lets that run before pairing.dispose(), otherwise
      // notifyListeners fires on an already-disposed ChangeNotifier.
      await sub.cancel();
      await inbound.close();
      pairing.dispose();
      deviceList.dispose();
    });
    expect(pairing.connected, isTrue);

    await tester.pumpWidget(wrapScreen(
      const RemoteInputScreen(),
      providers: [ChangeNotifierProvider<PairingModel>.value(value: pairing)],
    ));

    expect(find.text('Remote control'), findsNothing,
        reason: 'the connected view has its own hint text, not the empty '
            'state title');
    await tester.tap(find.text('Left'));
    await tester.pump();

    // onInboundSyncStream pushes an Identity handshake frame as soon as
    // the responder session opens, ahead of any input events -- so the
    // press/release pair are frames [1] and [2], not [0] and [1].
    expect(sentFrames, hasLength(3));
    final inputFrames = sentFrames.skip(1);
    for (final frame in inputFrames) {
      expect(frame.inputEvent.type,
          pb.InputEventType.INPUT_EVENT_TYPE_MOUSE_BUTTON);
      expect(frame.inputEvent.button, pb.MouseButton.MOUSE_BUTTON_LEFT);
    }
    expect(sentFrames[1].inputEvent.pressed, isTrue);
    expect(sentFrames[2].inputEvent.pressed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an active Shift modifier is applied to a sent key event',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    final inbound = StreamController<pb.SyncFrame>();
    final sentFrames = <pb.SyncFrame>[];
    final sub = pairing.onInboundSyncStream(inbound.stream).listen(sentFrames.add);
    addTearDown(() async {
      // inbound.close() schedules its onDone (-> PairingModel's
      // _closeInboundSession -> notifyListeners) as a microtask; awaiting
      // the close lets that run before pairing.dispose(), otherwise
      // notifyListeners fires on an already-disposed ChangeNotifier.
      await sub.cancel();
      await inbound.close();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const RemoteInputScreen(),
      providers: [ChangeNotifierProvider<PairingModel>.value(value: pairing)],
    ));

    await tester.tap(find.text('Shift'));
    await tester.pump();
    await tester.tap(find.text('Enter'));
    await tester.pump();

    // See the previous test's comment: an Identity handshake frame is
    // sent first, ahead of any input events. Enter also sends a
    // press+release pair, like the mouse button above.
    expect(sentFrames, hasLength(3));
    expect(sentFrames[1].inputEvent.modifiers, 1); // shift bit
    expect(sentFrames[1].inputEvent.keyCode, 0xff0d); // enter keysym
    expect(sentFrames[1].inputEvent.keyPressed, isTrue);
    expect(sentFrames[2].inputEvent.keyPressed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Each special key must go out as a KEY press+release pair carrying the
  // X11 keysym the daemon's Wayland backend maps to the physical key (see
  // proto RemoteInputEvent.key_code). Tapping the widget identified by
  // [finder] must emit exactly that keysym.
  //
  // T-E4 (Enter/Backspace/Arrows) and T-E5 (Tab/F1-F12) are all covered
  // here at the wire level; real uinput/Wayland injection cannot be
  // exercised in a widget test.
  Future<void> expectSpecialKey(
    WidgetTester tester, {
    required Finder finder,
    required int keysym,
  }) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    final inbound = StreamController<pb.SyncFrame>();
    final sentFrames = <pb.SyncFrame>[];
    final sub =
        pairing.onInboundSyncStream(inbound.stream).listen(sentFrames.add);
    addTearDown(() async {
      await sub.cancel();
      await inbound.close();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const RemoteInputScreen(),
      providers: [ChangeNotifierProvider<PairingModel>.value(value: pairing)],
    ));

    await tester.tap(finder);
    await tester.pump();

    // Frame [0] is the Identity handshake; [1]/[2] are press/release.
    expect(sentFrames, hasLength(3));
    for (final frame in sentFrames.skip(1)) {
      expect(frame.inputEvent.type, pb.InputEventType.INPUT_EVENT_TYPE_KEY);
      expect(frame.inputEvent.keyCode, keysym);
    }
    expect(sentFrames[1].inputEvent.keyPressed, isTrue);
    expect(sentFrames[2].inputEvent.keyPressed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  }

  // T-E4: Enter/Backspace/Arrows.
  testWidgets('Backspace sends the BackSpace keysym', (tester) async {
    await expectSpecialKey(tester,
        finder: find.text('Backspace'), keysym: 0xff08);
  });

  testWidgets('Enter sends the Return keysym', (tester) async {
    await expectSpecialKey(tester, finder: find.text('Enter'), keysym: 0xff0d);
  });

  testWidgets('Arrow keys send their directional keysyms', (tester) async {
    await expectSpecialKey(tester,
        finder: find.byIcon(Icons.keyboard_arrow_left), keysym: 0xff51);
    await expectSpecialKey(tester,
        finder: find.byIcon(Icons.keyboard_arrow_up), keysym: 0xff52);
    await expectSpecialKey(tester,
        finder: find.byIcon(Icons.keyboard_arrow_right), keysym: 0xff53);
    await expectSpecialKey(tester,
        finder: find.byIcon(Icons.keyboard_arrow_down), keysym: 0xff54);
  });

  // T-E5: Tab + F1-F12.
  testWidgets('Tab sends the Tab keysym', (tester) async {
    await expectSpecialKey(tester, finder: find.text('Tab'), keysym: 0xff09);
  });

  testWidgets('function keys send contiguous F1-F12 keysyms', (tester) async {
    // XK_F1 = 0xffbe .. XK_F12 = 0xffc9.
    for (var n = 1; n <= 12; n++) {
      await expectSpecialKey(tester,
          finder: find.text('F$n'), keysym: 0xffbe + (n - 1));
    }
  });
}
