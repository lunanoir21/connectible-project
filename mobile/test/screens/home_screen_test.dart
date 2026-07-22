import 'dart:convert';

import 'package:connectible_mobile/src/screens/home_screen.dart';
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
    // pairableEnabled: false so HomeScreen's startDiscovery() (fired via
    // an addPostFrameCallback as soon as this widget is pumped) never
    // reaches into the real `nsd` platform channel to advertise -- the
    // mDNS *browse* sweep it also kicks off is still real, but
    // MdnsService.sweep() already swallows every failure into
    // lastDiscoveryError, matching the existing widget_test.dart "App
    // launches" test's precedent of not needing to mock it.
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

  Future<void> disposeSoon(
      WidgetTester tester, PairingModel pairing, DeviceListModel deviceList) async {
    // Dispose synchronously here, not via addTearDown: DeviceListModel /
    // PairingModel own real timers (mDNS sweep, reconnect backoff), and
    // addTearDown callbacks run *after* Flutter's own pending-timer
    // invariant check at the end of the test body, which is too late to
    // satisfy it.
    await tester.pumpWidget(const SizedBox.shrink());
    pairing.dispose();
    deviceList.dispose();
  }

  testWidgets(
      'shows the not-paired status and empty device list, then lets an '
      'enabled Quick Action request a tab switch', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);

    int? requestedTab;

    await tester.pumpWidget(wrapScreen(
      HomeScreen(onNavigateTab: (i) => requestedTab = i),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    // No paired devices yet -- the status card's not-paired copy, and the
    // device list's empty state (no radar/tabs left to switch between).
    expect(find.text('No paired devices yet'), findsOneWidget);
    expect(find.text('No devices yet'), findsOneWidget);

    // Settings has no connection dependency, so it stays enabled and
    // navigates even with nothing paired.
    await tester.tap(find.widgetWithText(InkWell, 'Settings'));
    await tester.pump();
    expect(requestedTab, ShellTab.settings);

    await disposeSoon(tester, pairing, deviceList);
  });

  testWidgets(
      'renders the paired peer platform icon on its constellation node '
      '(T-E6)', (tester) async {
    // Seed a persisted paired Android device so DeviceListModel loads it
    // into its roster on construction -- exercising the same store path
    // addPairedDevice()/listDevices() write the peer's platform through.
    SharedPreferences.setMockInitialValues({
      'connectible.device_id': 'self-id',
      'connectible.paired_devices': jsonEncode([
        {
          'id': 'peer-android',
          'name': 'Pixel',
          'pairedAt': 1,
          'platform': 'PLATFORM_ANDROID',
        }
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final deviceList = DeviceListModel(prefs,
        deviceName: 'Test Phone', pairableEnabled: false);
    final pairing = buildPairing(deviceList);

    await tester.pumpWidget(wrapScreen(
      const HomeScreen(),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    // An Android peer maps to the phone glyph via the shared platformIcon()
    // helper -- the same one nearby devices would use.
    expect(find.byIcon(Icons.smartphone_outlined), findsOneWidget);

    await disposeSoon(tester, pairing, deviceList);
  });

  testWidgets(
      'disables connection-dependent Quick Actions until a session is '
      'active, but not Clipboard/Settings (T-106)', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);

    await tester.pumpWidget(wrapScreen(
      const HomeScreen(),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    InkWell inkWellFor(String label) =>
        tester.widget<InkWell>(find.widgetWithText(InkWell, label));

    expect(inkWellFor('Send file').onTap, isNull);
    expect(inkWellFor('Remote input').onTap, isNull);
    expect(inkWellFor('Clipboard history').onTap, isNotNull);
    expect(inkWellFor('Settings').onTap, isNotNull);

    await disposeSoon(tester, pairing, deviceList);
  });
}
