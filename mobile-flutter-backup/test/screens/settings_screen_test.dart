import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/i18n/strings.dart';
import 'package:connectible_mobile/src/screens/settings_screen.dart';
import 'package:connectible_mobile/src/services/notification_listener.dart';
import 'package:connectible_mobile/src/state/clipboard_model.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/notification_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:connectible_mobile/src/state/settings_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:connectible_mobile/src/theme/app_theme.dart';
// Our service `NotificationListener` (a plain abstract seam) collides by
// name with Flutter's `NotificationListener` widget; hide the widget here
// since this test only needs the service type.
import 'package:flutter/material.dart' hide NotificationListener;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_scaffold.dart';

/// Never-connected connection so [NotificationModel] never tries to send.
class _NoopConnection implements SyncConnection {
  @override
  bool get connected => false;
  @override
  String? get activePeerId => null;
  @override
  pb.ConnectibleClient? get uploadClient => null;
  @override
  pb.Identity get localIdentity => pb.Identity(deviceId: 'test');
  @override
  void sendFrame(pb.SyncFrame frame) {}
}

/// Notification listener stub: no access, empty streams, no platform channel.
class _NoopListener implements NotificationListener {
  @override
  Future<NotificationAccessState> get accessState async =>
      NotificationAccessState.notGranted;
  @override
  Future<bool> openAccessSettings() async => false;
  @override
  Stream<NotificationLifecycle> get lifecycle => const Stream.empty();
  @override
  Stream<NotificationEvent> get events => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(DeviceListModel, PairingModel, SettingsModel)> buildModels() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deviceList = DeviceListModel(prefs,
        deviceName: 'Test Phone', pairableEnabled: false);
    final pairing = PairingModel(
      deviceList: deviceList,
      onClipboardFrame: (_) {},
      onFileTransferStart: (_) {},
      onFileChunk: (_) {},
      onFileChunkRequest: (_) {},
      pairableEnabled: false,
    );
    final settings = SettingsModel(prefs);
    return (deviceList, pairing, settings);
  }

  Widget buildScreen(PairingModel pairing, SettingsModel settings,
          {ClipboardModel? clipboard}) =>
      wrapScreen(
        const SettingsScreen(),
        providers: [
          ChangeNotifierProvider<PairingModel>.value(value: pairing),
          ChangeNotifierProvider<SettingsModel>.value(value: settings),
          ChangeNotifierProvider<NotificationModel>(
            create: (_) => NotificationModel(
              connection: _NoopConnection(),
              listener: _NoopListener(),
            ),
          ),
          // Hour-long poll interval so the periodic clipboard timer can
          // never fire mid-test (the T-E10 hang class); the provider
          // disposes the model (and its timer) when the tree unmounts.
          if (clipboard == null)
            ChangeNotifierProvider<ClipboardModel>(
              create: (_) => ClipboardModel(
                connection: _NoopConnection(),
                pollInterval: const Duration(hours: 1),
              ),
            )
          else
            // `create` (not `.value`) + non-lazy so the provider owns and
            // disposes this pre-built model (cancelling its poll timer)
            // when the tree unmounts, before the pending-timer invariant
            // check runs.
            ChangeNotifierProvider<ClipboardModel>(
                create: (_) => clipboard, lazy: false),
        ],
      );

  testWidgets('renders appearance, language, discoverable and about sections',
      (tester) async {
    final (deviceList, pairing, settings) = await buildModels();
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(buildScreen(pairing, settings));

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Charcoal'), findsOneWidget);
    expect(find.text('Onyx'), findsOneWidget);
    expect(find.text('Graphite'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Türkçe'), findsOneWidget);
    expect(find.text('Discoverable'), findsOneWidget);
    // "About" is the last section, below the fold at the default test
    // viewport -- a real ListView only realizes sliver children near the
    // current viewport, so it must be scrolled into view first (same as
    // shell_test.dart).
    await tester.scrollUntilVisible(find.text('About'), 200);
    await tester.pump();
    expect(find.text('About'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('TLS 1.3, PIN-verified pairing'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping a theme card switches the active theme', (tester) async {
    final (deviceList, pairing, settings) = await buildModels();
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });
    expect(settings.theme, ThemeId.charcoal);

    await tester.pumpWidget(buildScreen(pairing, settings));
    await tester.tap(find.text('Onyx'));
    await tester.pump();

    expect(settings.theme, ThemeId.onyx);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the Turkish language row switches the locale',
      (tester) async {
    final (deviceList, pairing, settings) = await buildModels();
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });
    expect(settings.locale, AppLocale.en);

    await tester.pumpWidget(buildScreen(pairing, settings));
    await tester.tap(find.text('Türkçe'));
    await tester.pump();

    expect(settings.locale, AppLocale.tr);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('toggling discoverable off updates SettingsModel and is '
      'harmless against an already-disabled PairingModel server (T-308)',
      (tester) async {
    final (deviceList, pairing, settings) = await buildModels();
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });
    expect(settings.pairableEnabled, isTrue);
    expect(pairing.pairableEnabled, isFalse);

    await tester.pumpWidget(buildScreen(pairing, settings));
    // The Discoverable section is above the Clipboard section (which also
    // has toggles), so its Switch is the first in tree order.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(settings.pairableEnabled, isFalse);
    // Toggling to the same effective PairingModel state (already off) is a
    // no-op per PairingModel.setPairableEnabled, so it stays false and
    // never attempted to bind a real inbound server.
    expect(pairing.pairableEnabled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('toggling clipboard auto-monitor updates both the persisted '
      'setting and the live ClipboardModel (T-B11)', (tester) async {
    final (deviceList, pairing, settings) = await buildModels();
    final clipboard = ClipboardModel(
      connection: _NoopConnection(),
      pollInterval: const Duration(hours: 1),
    );
    // `clipboard` is disposed by its provider on unmount (see buildScreen),
    // so it is intentionally not disposed here.
    addTearDown(() {
      pairing.dispose();
      deviceList.dispose();
    });
    expect(settings.clipboardAutoMonitor, isTrue);
    expect(clipboard.autoMonitor, isTrue);

    await tester.pumpWidget(buildScreen(pairing, settings, clipboard: clipboard));
    final label = find.text('Auto-send copies from this phone');
    await tester.scrollUntilVisible(label, 200);
    await tester.pump();
    // Target the Switch inside the auto-monitor row specifically (robust
    // against scroll position / how many switches are realized).
    final autoMonitorRow =
        find.ancestor(of: label, matching: find.byType(Row)).first;
    await tester
        .tap(find.descendant(of: autoMonitorRow, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(settings.clipboardAutoMonitor, isFalse);
    expect(clipboard.autoMonitor, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
