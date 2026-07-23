import 'dart:io';

import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/screens/transfers_screen.dart';
import 'package:connectible_mobile/src/services/save_file_service.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/file_transfer_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_scaffold.dart';

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

/// Records "Save to..." requests instead of touching any platform
/// channel (T-X6) -- the screen only ever hands over a source path and
/// a file name, never bytes.
class _FakeSaveFileService implements SaveFileService {
  SaveFileOutcome outcome = SaveFileOutcome.saved;
  final calls = <({String sourcePath, String fileName})>[];

  @override
  Future<SaveFileOutcome> saveAs({
    required String sourcePath,
    required String fileName,
    String? dialogTitle,
  }) async {
    calls.add((sourcePath: sourcePath, fileName: fileName));
    return outcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> testPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  Future<DeviceListModel> buildDeviceList() async {
    return DeviceListModel(await testPrefs(),
        deviceName: 'Test Phone', pairableEnabled: false);
  }

  PairingModel buildPairing(DeviceListModel deviceList) => PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        pairableEnabled: false,
      );

  testWidgets('shows the empty state and a disabled Send file button when idle',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    final fileTransfer = FileTransferModel(
        connection: _FakeConnection(), prefs: await testPrefs());
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    expect(find.text('No transfers yet'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renders in-flight and finished transfer rows with a cancel '
      'affordance only on active outgoing transfers', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList)..connected = true;
    final fileTransfer = FileTransferModel(
        connection: _FakeConnection(), prefs: await testPrefs())
      ..transfers = {
        'outgoing-active': const TransferProgress(
          transferId: 'outgoing-active',
          fileName: 'sending.bin',
          bytesTransferred: 50,
          totalBytes: 100,
          direction: TransferDirection.outgoing,
        ),
        'incoming-done': const TransferProgress(
          transferId: 'incoming-done',
          fileName: 'received.bin',
          bytesTransferred: 100,
          totalBytes: 100,
          direction: TransferDirection.incoming,
          completed: true,
        ),
        'outgoing-failed': const TransferProgress(
          transferId: 'outgoing-failed',
          fileName: 'broken.bin',
          bytesTransferred: 10,
          totalBytes: 100,
          direction: TransferDirection.outgoing,
          failed: true,
        ),
      };
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    expect(find.text('sending.bin'), findsOneWidget);
    expect(find.text('received.bin'), findsOneWidget);
    expect(find.text('broken.bin'), findsOneWidget);
    expect(find.textContaining('Sending'), findsOneWidget);
    expect(find.textContaining('Completed'), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);

    // Only the active outgoing transfer offers a cancel button.
    expect(find.byTooltip('Cancel transfer'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel transfer'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'renders persisted history from a previous session when there are no '
      'live transfers (Phase J)', (tester) async {
    // buildDeviceList first: its own testPrefs() resets the mock store,
    // so the history blob must be seeded *after* it to survive.
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    // Pre-populate prefs with a history blob exactly as _saveHistory
    // writes it, simulating an app restart: the in-memory transfers map
    // is empty, but the persisted entry must still render (and must not
    // be masked by the empty state).
    SharedPreferences.setMockInitialValues({
      'connectible.transfer_history':
          '[{"transferId":"old-1","peerDeviceId":"peer-1",'
              '"fileName":"archive.zip","totalBytes":4096,'
              '"direction":"incoming","status":"completed",'
              '"startedAtMs":1000,"finishedAtMs":2000}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final fileTransfer =
        FileTransferModel(connection: _FakeConnection(), prefs: prefs);
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    expect(fileTransfer.transfers, isEmpty);

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    expect(find.text('No transfers yet'), findsNothing);
    expect(find.text('archive.zip'), findsOneWidget);
    expect(find.textContaining('Completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a history row shows the resolved peer name and a relative time '
      '(T-X24)', (tester) async {
    final deviceList = await buildDeviceList();
    // The persisted entry's peerDeviceId resolves against the live
    // paired roster -- the row must show "Pixel", not the raw id.
    deviceList.addPairedDevice(
        pb.Identity(deviceId: 'peer-1', deviceName: 'Pixel'));
    final pairing = buildPairing(deviceList);
    SharedPreferences.setMockInitialValues({
      'connectible.transfer_history':
          '[{"transferId":"named-1","peerDeviceId":"peer-1",'
              '"fileName":"photo.jpg","totalBytes":4096,'
              '"direction":"incoming","status":"completed",'
              '"startedAtMs":1000,"finishedAtMs":2000}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final fileTransfer =
        FileTransferModel(connection: _FakeConnection(), prefs: prefs);
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    // Resolved peer name, joined with a relative-time label (finishedAtMs
    // 2000ms is deep in the past, so this always renders the "days ago"
    // form -- the exact count isn't the point, only that some time label
    // is present alongside the resolved name).
    expect(find.textContaining('Pixel'), findsOneWidget);
    expect(find.textContaining('Pixel - '), findsOneWidget);
    expect(find.textContaining('d ago'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'shows 0% (not a misleading full bar) for a restored genuine failure '
      '(T-X33)', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    SharedPreferences.setMockInitialValues({
      'connectible.transfer_history':
          '[{"transferId":"broken-1","peerDeviceId":"peer-1",'
              '"fileName":"broken.bin","totalBytes":4096,'
              '"direction":"incoming","status":"failed",'
              '"startedAtMs":1000,"finishedAtMs":2000}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final fileTransfer =
        FileTransferModel(connection: _FakeConnection(), prefs: prefs);
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    await tester.pumpAndSettle();
    expect(find.text('broken.bin'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets(
      '"Save to..." on a restored history row whose file was deleted from '
      'disk degrades to the unavailable notice, not a crash (T-X5)',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    // A persisted completed incoming entry whose localPath no longer
    // exists on disk -- e.g. the user cleared app storage between runs.
    SharedPreferences.setMockInitialValues({
      'connectible.transfer_history':
          '[{"transferId":"gone-1","peerDeviceId":"peer-1",'
              '"fileName":"gone.bin","totalBytes":4096,'
              '"direction":"incoming","status":"completed",'
              '"startedAtMs":1000,"finishedAtMs":2000,'
              '"localPath":"/nonexistent/received/gone.bin"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final fileTransfer =
        FileTransferModel(connection: _FakeConnection(), prefs: prefs);
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    // The restored row still offers the way out of app storage...
    expect(find.text('Save to...'), findsOneWidget);
    await tester.tap(find.text('Save to...'));
    // _saveTo's File.exists() is real dart:io async; give the event loop
    // a real-time turn so it can complete inside the FakeAsync test zone.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // ...and a genuinely deleted file surfaces the notice, no crash.
    expect(find.text('File is no longer available'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      '"Save to..." hands the on-disk path to the streaming save service '
      '(never bytes) and reports success (T-X6)', (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    // A real on-disk file the persisted history entry points at, so the
    // exists() check passes and the service is actually invoked.
    final sourceFile = File(
        '${Directory.systemTemp.path}/tx6_saveto_${DateTime.now().microsecondsSinceEpoch}.bin')
      ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
    addTearDown(() {
      if (sourceFile.existsSync()) sourceFile.deleteSync();
    });
    SharedPreferences.setMockInitialValues({
      'connectible.transfer_history':
          '[{"transferId":"keep-1","peerDeviceId":"peer-1",'
              '"fileName":"archive.zip","totalBytes":4096,'
              '"direction":"incoming","status":"completed",'
              '"startedAtMs":1000,"finishedAtMs":2000,'
              '"localPath":"${sourceFile.path}"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final fileTransfer =
        FileTransferModel(connection: _FakeConnection(), prefs: prefs);
    final saveService = _FakeSaveFileService();
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      TransfersScreen(saveFileService: saveService),
      providers: [
        ChangeNotifierProvider<DeviceListModel>.value(value: deviceList),
        ChangeNotifierProvider<PairingModel>.value(value: pairing),
        ChangeNotifierProvider<FileTransferModel>.value(value: fileTransfer),
      ],
    ));

    await tester.tap(find.text('Save to...'));
    // _saveTo's File.exists() is real dart:io async; give the event loop
    // a real-time turn so it can complete inside the FakeAsync test zone.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(saveService.calls.single.sourcePath, sourceFile.path);
    expect(saveService.calls.single.fileName, 'archive.zip');
    expect(find.text('File saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
