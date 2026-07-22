import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/screens/transfers_screen.dart';
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

  testWidgets('shows the empty state and a disabled Send file button when idle',
      (tester) async {
    final deviceList = await buildDeviceList();
    final pairing = buildPairing(deviceList);
    final fileTransfer = FileTransferModel(connection: _FakeConnection());
    addTearDown(() {
      fileTransfer.dispose();
      pairing.dispose();
      deviceList.dispose();
    });

    await tester.pumpWidget(wrapScreen(
      const TransfersScreen(),
      providers: [
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
    final fileTransfer = FileTransferModel(connection: _FakeConnection())
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
}
