import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceListModel.forgetDevice (T-307)', () {
    test('permanently removes a paired device from the roster', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(model.dispose);

      model.addPairedDevice(pb.Identity(
        deviceId: 'peer-1',
        deviceName: 'Peer One',
      ));
      expect(model.knownDevices().map((d) => d.deviceId), contains('peer-1'));
      expect(model.devices.map((d) => d.deviceId), contains('peer-1'));

      model.forgetDevice('peer-1');

      expect(
          model.knownDevices().map((d) => d.deviceId), isNot(contains('peer-1')));
      expect(model.devices.map((d) => d.deviceId), isNot(contains('peer-1')));
    });

    test('forgetting is persisted across a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(model.dispose);

      model.addPairedDevice(
          pb.Identity(deviceId: 'peer-2', deviceName: 'Peer Two'));
      model.forgetDevice('peer-2');

      final reloaded = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(reloaded.dispose);
      expect(reloaded.knownDevices().map((d) => d.deviceId),
          isNot(contains('peer-2')));
    });

    test('forgetting an unknown device id is a harmless no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(model.dispose);

      model.addPairedDevice(
          pb.Identity(deviceId: 'peer-3', deviceName: 'Peer Three'));
      model.forgetDevice('does-not-exist');

      expect(model.knownDevices().map((d) => d.deviceId), contains('peer-3'));
    });
  });

  group('DeviceListModel TOFU pin store (T-C4)', () {
    test('records, reads back, and persists a cert fingerprint', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(model.dispose);

      model.addPairedDevice(
          pb.Identity(deviceId: 'peer-1', deviceName: 'Peer One'));

      // No pin yet (backfill target).
      expect(model.pinnedFingerprint('peer-1'), isNull);

      model.recordFingerprint('peer-1', 'abc123');
      expect(model.pinnedFingerprint('peer-1'), 'abc123');

      // Survives a reload from persisted storage.
      final reloaded = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(reloaded.dispose);
      expect(reloaded.pinnedFingerprint('peer-1'), 'abc123');
    });

    test('recording for an unknown device is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(model.dispose);

      model.recordFingerprint('ghost', 'zzz');
      expect(model.pinnedFingerprint('ghost'), isNull);
    });
  });
}
