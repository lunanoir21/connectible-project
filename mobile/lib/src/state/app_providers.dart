import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_model.dart';
import 'clipboard_model.dart';
import 'device_list_model.dart';
import 'file_transfer_model.dart';
import 'notification_model.dart';
import 'pairing_model.dart';
import 'sync_connection.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

/// Builds the `ChangeNotifier` providers the app depends on (T-204),
/// wiring their cross-model dependencies in one place so `main.dart` and
/// widget tests can't drift from each other.
///
/// [PairingModel] owns the active session and needs to hand inbound
/// clipboard/file frames to [ClipboardModel]/[FileTransferModel], while
/// those two models need to push *outbound* frames through the session
/// [PairingModel] owns -- a construction cycle. `late final pairing` plus
/// [_LazyConnection] (a [SyncConnection] that resolves `pairing` lazily,
/// only once actual traffic flows) breaks that cycle without introducing
/// a fifth god-object: by the time any frame is sent, `pairing` is always
/// already assigned.
List<SingleChildWidget> buildAppStateProviders(
  SharedPreferences prefs, {
  required String deviceName,
  bool pairableEnabled = true,
  bool clipboardAutoMonitor = true,
  bool clipboardAutoApply = true,
}) {
  final deviceList = DeviceListModel(prefs,
      deviceName: deviceName, pairableEnabled: pairableEnabled);

  late final PairingModel pairing;
  final clipboard = ClipboardModel(
    connection: _LazyConnection(() => pairing),
    autoMonitor: clipboardAutoMonitor,
    autoApply: clipboardAutoApply,
  );
  final fileTransfer = FileTransferModel(
      connection: _LazyConnection(() => pairing), prefs: prefs);
  // Constructed before `pairing` (like clipboard/fileTransfer above) so
  // its `handleInbound` (T-K4) can be wired into PairingModel's
  // constructor directly, rather than needing a second _LazyConnection-
  // style indirection just for one callback.
  final notifications =
      NotificationModel(connection: _LazyConnection(() => pairing));
  pairing = PairingModel(
    deviceList: deviceList,
    onClipboardFrame: clipboard.handleInbound,
    onNotificationFrame: notifications.handleInbound,
    onPrepareUpload: fileTransfer.handlePrepareUpload,
    onUploadFile: fileTransfer.handleUploadFile,
    pairableEnabled: pairableEnabled,
  );
  // Constructed after `pairing` is assigned: unlike clipboard/fileTransfer
  // (which only touch the connection when a frame flows), BatteryModel
  // eagerly reports at construction, so it must not run before the lazy
  // `pairing` target exists.
  final battery = BatteryModel(connection: _LazyConnection(() => pairing));

  // `create:` (not `.value`) so each provider disposes its model when
  // removed from the tree -- `.value` deliberately opts out of that,
  // which is wrong here since these models are not shared with anything
  // outside this provider subtree.
  return [
    ChangeNotifierProvider<DeviceListModel>(create: (_) => deviceList),
    ChangeNotifierProvider<PairingModel>(create: (_) => pairing),
    ChangeNotifierProvider<ClipboardModel>(create: (_) => clipboard),
    ChangeNotifierProvider<FileTransferModel>(create: (_) => fileTransfer),
    // `lazy: false` for these two background senders: they are constructed
    // eagerly above (BatteryModel even starts a periodic timer in its
    // constructor) and no widget necessarily *reads* them, so a lazy
    // provider would never take ownership and never dispose them -- leaking
    // BatteryModel's timer past widget-tree teardown. Non-lazy makes the
    // provider own them from mount, so unmount disposes them.
    ChangeNotifierProvider<BatteryModel>(create: (_) => battery, lazy: false),
    ChangeNotifierProvider<NotificationModel>(
        create: (_) => notifications, lazy: false),
  ];
}

/// Indirection that lets [ClipboardModel]/[FileTransferModel] be
/// constructed before the [PairingModel] they ultimately talk to exists,
/// by resolving it lazily on first use instead of capturing it directly.
class _LazyConnection implements SyncConnection {
  _LazyConnection(this._resolve);
  final SyncConnection Function() _resolve;

  @override
  bool get connected => _resolve().connected;

  @override
  String? get activePeerId => _resolve().activePeerId;

  @override
  void sendFrame(pb.SyncFrame frame) => _resolve().sendFrame(frame);

  @override
  pb.ConnectibleClient? get uploadClient => _resolve().uploadClient;

  @override
  pb.Identity get localIdentity => _resolve().localIdentity;
}
