import 'dart:convert';

import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/screens/home_screen.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_scaffold.dart';

/// [PairingModel] with a fixed active-peer id, standing in for the state
/// right after a successful phone-initiated pair (T-X1) without needing a
/// live loopback session inside a widget test. `activePeerId` is what the
/// Home status line resolves against the paired roster.
class _ActiveSessionPairing extends PairingModel {
  _ActiveSessionPairing(DeviceListModel deviceList)
      : super(
          deviceList: deviceList,
          onClipboardFrame: (_) {},
          pairableEnabled: false,
        );

  @override
  String? get activePeerId => 'peer-android';
}

/// A [PairingModel] whose failure state can be driven directly, standing in
/// for a security-relevant automatic-reconnect failure -- a real
/// fingerprint mismatch needs a peer whose TLS cert changed, impractical to
/// stage inside a widget test. `emitError` mirrors exactly what the model's
/// own `_setError` does before it notifies.
class _ErrorPairing extends PairingModel {
  _ErrorPairing(DeviceListModel deviceList)
      : super(
          deviceList: deviceList,
          onClipboardFrame: (_) {},
          pairableEnabled: false,
        );

  void emitError(String message, PairingErrorKind kind) {
    lastError = message;
    lastErrorKind = kind;
    lastErrorSeq++;
    notifyListeners();
  }
}

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
      'status line names the active peer once its paired-roster row exists '
      '(T-X1/T-X4)', (tester) async {
    // The paired roster carries the active peer -- exactly what T-X1's
    // requester-side persistence guarantees after a phone-initiated pair.
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
    final pairing = _ActiveSessionPairing(deviceList)..connected = true;

    await tester.pumpWidget(wrapScreen(
      const HomeScreen(),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    // Not the generic "Connected" -- the roster row resolves the name.
    expect(find.text('Connected to Pixel'), findsOneWidget);

    await disposeSoon(tester, pairing, deviceList);
  });

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
      'offers a direct Connect action for a paired-but-offline device '
      'rediscovered via mDNS, instead of forcing Forget + re-pair',
      (tester) async {
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
    // Rediscovered on the LAN under its current address even though the
    // active session was lost (e.g. app restart) -- this is what makes a
    // direct reconnect possible instead of Forget + a fresh PIN exchange.
    deviceList.nearby = const [
      NearbyDevice(
        deviceId: 'peer-android',
        deviceName: 'Pixel',
        platform: 'PLATFORM_ANDROID',
        host: '192.168.1.40',
        port: 58231,
      ),
    ];
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

    await tester.tap(find.text('Pixel'));
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Forget device'), findsOneWidget);

    await disposeSoon(tester, pairing, deviceList);
  });

  testWidgets(
      'does not offer Connect for a paired-but-offline device that has '
      'not been rediscovered on the LAN', (tester) async {
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

    await tester.tap(find.text('Pixel'));
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsNothing);
    expect(find.text('Forget device'), findsOneWidget);

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

  testWidgets(
      'a connect/pairing failure surfaces its message as a snackbar on Home '
      '(T-X19)', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = _ErrorPairing(deviceList);

    await tester.pumpWidget(wrapScreen(
      const HomeScreen(),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    // Stands in for startPair/reconnect recording a generic failure: the
    // model's real connect-failure paths do exactly this set-then-notify
    // (that they set lastError on a genuine failed dial is covered by
    // pairing_model_test.dart). Before the fix Home surfaced none of them.
    pairing.emitError('Pairing was rejected', PairingErrorKind.generic);
    await tester.pump(); // deliver the snackbar the listener enqueued
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SnackBar), findsOneWidget);
    // A generic error surfaces the model's own message verbatim.
    expect(find.text('Pairing was rejected'), findsOneWidget);

    await disposeSoon(tester, pairing, deviceList);
  });

  testWidgets(
      'the reconnect fingerprint-changed warning shows its dedicated '
      'localized string, not the raw model fallback (T-X19)', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = _ErrorPairing(deviceList);

    await tester.pumpWidget(wrapScreen(
      const HomeScreen(),
      disableAnimations: true,
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
      ],
    ));
    await tester.pumpAndSettle();

    pairing.emitError(
        'raw english fallback', PairingErrorKind.fingerprintChanged);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.text("This device's security key changed since pairing. "
            'Forget it and pair again to reconnect.'),
        findsOneWidget);
    expect(find.text('raw english fallback'), findsNothing);

    await disposeSoon(tester, pairing, deviceList);
  });
}
