import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/connectible_server.dart' show kServerPort;
import '../state/device_list_model.dart';
import '../state/pairing_model.dart';
import '../state/settings_model.dart';
import '../theme/app_theme.dart';
import '../widgets/device_action_sheet.dart';
import '../widgets/pairing_sheet.dart';
import '../widgets/ui.dart' show AppCard, EmptyState, Eyebrow, platformIcon;
import 'pair_landing_screen.dart';

/// Bottom-nav tab indices in [AppShell], duplicated here (rather than
/// imported, which would create a shell <-> home_screen import cycle
/// since shell.dart already imports this file) so the quick-action
/// cards can switch the outer shell tab. Keep in sync with
/// AppShell._screens' order.
class ShellTab {
  static const int home = 0;
  static const int clipboard = 1;
  static const int transfers = 2;
  static const int input = 3;
  static const int settings = 4;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onNavigateTab});

  /// Requests the enclosing [AppShell] switch to the given [ShellTab]
  /// index. Null (e.g. in isolated widget tests) makes quick actions
  /// that need it a no-op instead of throwing.
  final ValueChanged<int>? onNavigateTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Re-entrancy guard for [_onTapNearby] (mirrors pair_scan_screen.dart's
  /// `_handled`): a rapid double-tap on the same nearby device would
  /// otherwise fire two concurrent `startPair` calls, leaving the first
  /// gRPC connection dangling with nothing to clean it up. Set before the
  /// async pairing call starts; reset on failure so a genuine retry after
  /// an error is not permanently locked out, but left set on success (the
  /// PairingSheet takes over from there, same as pair_scan_screen.dart).
  bool _pairing = false;

  /// The [PairingModel] we listen to for connect/pairing failures, so they
  /// surface as a snackbar on Home (T-X19) instead of failing silently.
  /// Held so the listener can be removed in [dispose].
  PairingModel? _pairingModel;

  /// The last error sequence we have already shown, so a fresh failure
  /// (even one whose text repeats a previous one) is surfaced exactly once.
  /// Seeded from the model when we attach, so an error that predates this
  /// screen mounting is not replayed.
  int _seenErrorSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DeviceListModel>().startDiscovery();
      final pairing = context.read<PairingModel>();
      _pairingModel = pairing;
      _seenErrorSeq = pairing.lastErrorSeq;
      pairing.addListener(_onPairingError);
    });
  }

  @override
  void dispose() {
    _pairingModel?.removeListener(_onPairingError);
    super.dispose();
  }

  /// Surfaces a connect/pairing failure as a snackbar when [PairingModel]
  /// records a new one. Tapping a nearby device, "connect by address", and
  /// the automatic-reconnect fingerprint-changed security warning all reach
  /// the user this way (previously they failed with zero feedback). The
  /// fingerprint case gets its own dedicated, translated string; everything
  /// else surfaces the model's message. Only speaks up while Home is the
  /// visible route -- a pairing/scan screen pushed on top surfaces its own
  /// errors, so this avoids doubling them.
  void _onPairingError() {
    final pairing = _pairingModel;
    if (pairing == null || !mounted) return;
    if (pairing.lastErrorSeq == _seenErrorSeq) return;
    _seenErrorSeq = pairing.lastErrorSeq;
    final message = pairing.lastError;
    if (message == null) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final s = context.strings;
    final text = pairing.lastErrorKind == PairingErrorKind.fingerprintChanged
        ? s.t('home.fingerprintChanged')
        : message;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Manual pairing (no mDNS): the user types the peer's address, we
  /// synthesize a [NearbyDevice] from it and feed it into the same
  /// connect-by-host:port flow discovery would have produced. The gRPC
  /// client dials host:port over TLS directly -- multicast/mDNS is only
  /// ever used to *find* that address, never to connect.
  /// Toggles whether this phone runs its inbound server -- i.e. whether
  /// another device can discover it, pair into it, and send it files.
  /// Persists via SettingsModel and applies live via PairingModel (which
  /// starts/stops the ConnectibleServer + mDNS advertisement), mirroring
  /// the Settings screen's toggle so both surfaces stay in sync.
  Future<void> _setReceiving(BuildContext context, bool enabled) async {
    context.read<SettingsModel>().setPairableEnabled(enabled);
    await context.read<PairingModel>().setPairableEnabled(enabled);
  }

  void _openPairLanding(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PairLandingScreen()));
  }

  Future<void> _openManualConnect(BuildContext context) async {
    final result = await ManualConnectSheet.show(context);
    if (!mounted || result == null) return;
    await _onTapNearby(NearbyDevice(
      deviceId: 'manual:${result.$1}:${result.$2}',
      deviceName: result.$1,
      platform: '',
      host: result.$1,
      port: result.$2,
    ));
  }

  Future<void> _onTapNearby(NearbyDevice device) async {
    if (_pairing) return;
    _pairing = true;
    final model = context.read<PairingModel>();
    final ok = await model.startPair(device);
    if (!mounted) return;
    final pending = model.pendingPairing;
    if (ok && pending != null) {
      await PairingSheet.show(context,
          deviceName: device.deviceName,
          pinExpiresAtMs: pending.pinExpiresAtMs);
      if (!mounted) return;
      // Unlike pair_scan_screen.dart (which navigates away right after a
      // successful pair, so its `_handled` never needs to be reset),
      // HomeScreen stays on screen -- reset once the sheet closes so a
      // later tap on another device isn't permanently locked out.
      _pairing = false;
    } else {
      _pairing = false;
    }
  }

  /// Long-press/tap menu for a device in the constellation. For an
  /// unpaired nearby star the primary action is Connect, initiated from
  /// this side even though pairing is bidirectional overall -- the phone
  /// also runs its own gRPC/TLS server (ConnectibleServer) so a desktop
  /// peer can initiate pairing to this phone instead, in which case
  /// PairingModel's incomingPairings stream surfaces the responder PIN
  /// sheet. A paired star offers Info / Disconnect / Forget.
  Future<void> _showActions(BuildContext context,
      {DeviceInfo? paired, NearbyDevice? nearby}) async {
    final s = context.strings;
    final pairing = context.read<PairingModel>();
    final deviceList = context.read<DeviceListModel>();

    final actions = <DeviceAction>[];
    if (nearby != null) {
      actions.add(DeviceAction(
        icon: Icons.link,
        label: s.t('menu.connect'),
        onTap: () => _onTapNearby(nearby),
      ));
      actions.add(DeviceAction(
        icon: Icons.info_outline,
        label: s.t('menu.info'),
        onTap: () => _showInfo(context, nearby: nearby),
      ));
    } else if (paired != null) {
      actions.add(DeviceAction(
        icon: Icons.info_outline,
        label: s.t('menu.info'),
        onTap: () => _showInfo(context, paired: paired),
      ));
      if (paired.online) {
        actions.add(DeviceAction(
          icon: Icons.link_off,
          label: s.t('menu.disconnect'),
          danger: true,
          onTap: () => pairing.disconnect(),
        ));
      } else {
        // Paired but not currently connected -- if mDNS has rediscovered
        // this same device on the LAN, offer a direct reconnect instead
        // of forcing Forget + a fresh PIN exchange. No match means it's
        // not currently reachable (off/asleep/different network) and
        // there's nothing to connect to yet.
        final rediscovered = context
            .read<DeviceListModel>()
            .nearby
            .where((n) => n.deviceId == paired.deviceId)
            .firstOrNull;
        if (rediscovered != null) {
          actions.add(DeviceAction(
            icon: Icons.link,
            label: s.t('menu.connect'),
            onTap: () => pairing.reconnectToPeer(rediscovered),
          ));
        }
      }
      actions.add(DeviceAction(
        icon: Icons.person_remove_outlined,
        label: s.t('menu.forget'),
        danger: true,
        onTap: () => _forgetDevice(pairing, deviceList, paired.deviceId),
      ));
    }
    actions.add(DeviceAction(
      icon: Icons.refresh,
      label: s.t('menu.refresh'),
      onTap: () => _refreshDevicesAndRoster(context),
    ));

    await DeviceActionSheet.show(
      context,
      title: paired?.deviceName ?? nearby!.deviceName,
      subtitle: nearby != null
          ? _platformLabel(nearby.platform)
          : s.t('home.paired'),
      actions: actions,
    );
  }

  Future<void> _showInfo(BuildContext context,
      {DeviceInfo? paired, NearbyDevice? nearby}) async {
    final s = context.strings;
    final p = context.palette;
    final rows = <MapEntry<String, String>>[
      MapEntry(s.t('info.name'), paired?.deviceName ?? nearby!.deviceName)
    ];
    if (nearby != null) {
      rows.add(MapEntry(s.t('info.platform'), _platformLabel(nearby.platform)));
      rows.add(MapEntry(s.t('info.address'), '${nearby.host}:${nearby.port}'));
      rows.add(MapEntry(s.t('info.deviceId'), nearby.deviceId));
    } else if (paired != null) {
      rows.add(MapEntry(s.t('info.status'),
          paired.online ? s.t('common.online') : s.t('common.offline')));
      if (paired.platform.isNotEmpty) {
        rows.add(
            MapEntry(s.t('info.platform'), _platformLabel(paired.platform)));
      }
      rows.add(MapEntry(s.t('info.deviceId'), paired.deviceId));
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.lineStrong),
        ),
        title: Text(s.t('info.title'),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows) ...[
              Text(row.key.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10, letterSpacing: 1.2, color: p.inkFaint)),
              const SizedBox(height: 2),
              Text(row.value, style: TextStyle(fontSize: 14, color: p.ink)),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('info.done'), style: TextStyle(color: p.ink)),
          ),
        ],
      ),
    );
  }

  String _platformLabel(String platform) {
    final p = platform.toUpperCase();
    if (p.contains('ANDROID')) return 'Android';
    if (p.contains('IOS')) return 'iOS';
    if (p.contains('MACOS')) return 'macOS';
    if (p.contains('WINDOWS')) return 'Windows';
    if (p.contains('WAYLAND')) return 'Linux (Wayland)';
    if (p.contains('LINUX')) return 'Linux';
    return platform;
  }

  Future<void> _refreshAll(BuildContext context) =>
      _refreshDevicesAndRoster(context);

  /// Permanently removes a paired device from the local roster (T-307).
  /// If it is also the currently active session, drop that connection
  /// first so the phone does not keep talking to a device it just
  /// "forgot" -- re-pairing afterward requires a fresh PIN exchange.
  Future<void> _forgetDevice(
      PairingModel pairing, DeviceListModel deviceList, String deviceId) async {
    if (pairing.activePeerId == deviceId) {
      await pairing.disconnect();
    }
    deviceList.forgetDevice(deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final model = context.watch<DeviceListModel>();
    final pairing = context.watch<PairingModel>();

    final paired = model.devices;
    final pairedIds = paired.map((d) => d.deviceId).toSet();
    final pairable =
        model.nearby.where((d) => !pairedIds.contains(d.deviceId)).toList();
    final onlineCount = paired.where((d) => d.online).length;

    return RefreshIndicator(
      onRefresh: () => _refreshDevicesAndRoster(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          _Eyebrow(
            deviceName: model.deviceName,
            palette: p,
            strings: s,
            onRefresh: () => _refreshAll(context),
          ),
          const SizedBox(height: 8),
          _HomeDeviceList(
            deviceName: model.deviceName,
            paired: paired,
            pairable: pairable,
            palette: p,
            strings: s,
            onTapPaired: (d) => _showActions(context, paired: d),
            onTapNearby: (d) => _onTapNearby(d),
          ),
          const SizedBox(height: 14),
          _StatusLine(
            deviceName: model.deviceName,
            devices: paired,
            onlineCount: onlineCount,
            nearbyCount: pairable.length,
            pairing: pairing,
            palette: p,
            strings: s,
          ),
          const SizedBox(height: 28),
          _QuickActionsGrid(
            connected: pairing.connected,
            onlineCount: onlineCount,
            palette: p,
            strings: s,
            onNavigateTab: widget.onNavigateTab,
          ),
          const SizedBox(height: 18),
          _ReceivingCard(
            enabled: pairing.pairableEnabled,
            palette: p,
            strings: s,
            onChanged: (v) => _setReceiving(context, v),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _openPairLanding(context),
                  icon: Icon(Icons.qr_code_scanner,
                      size: 16, color: p.inkMuted),
                  label: Text(s.t('pairing.landing.cta'),
                      style: TextStyle(fontSize: 13, color: p.inkMuted)),
                ),
                Container(width: 1, height: 14, color: p.line),
                TextButton.icon(
                  onPressed: () => _openManualConnect(context),
                  icon: Icon(Icons.link, size: 16, color: p.inkMuted),
                  label: Text(s.t('home.connectByAddress'),
                      style: TextStyle(fontSize: 13, color: p.inkMuted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Re-scans mDNS *and* re-fetches the paired roster from the active
/// session (if any) -- the two independent operations behind the old
/// monolithic AppModel's refresh(), now split across
/// DeviceListModel/PairingModel.
Future<void> _refreshDevicesAndRoster(BuildContext context) async {
  // Read both models before the first await -- BuildContext must not be
  // touched again once an async gap has passed.
  final deviceList = context.read<DeviceListModel>();
  final pairing = context.read<PairingModel>();
  await deviceList.refresh();
  await pairing.refreshDevices();
}

// ===== Eyebrow =====

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({
    required this.deviceName,
    required this.palette,
    required this.strings,
    required this.onRefresh,
  });

  final String deviceName;
  final AppPalette palette;
  final AppStrings strings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    return Row(
      children: [
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                    text: s.t('status.thisDevice').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                        color: p.inkFaint)),
                TextSpan(
                    text: '  /  ',
                    style: TextStyle(fontSize: 11, color: p.inkGhost)),
                TextSpan(
                    text: deviceName.isEmpty ? 'Me' : deviceName,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: p.inkMuted)),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onRefresh,
          icon: Icon(Icons.refresh, size: 15, color: p.inkMuted),
          label: Text(s.t('menu.refresh'),
              style: TextStyle(fontSize: 12, color: p.inkMuted)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

// ===== Status Line =====
// One quiet line under the picture, restating in words what the
// constellation already shows.

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.deviceName,
    required this.devices,
    required this.onlineCount,
    required this.nearbyCount,
    required this.pairing,
    required this.palette,
    required this.strings,
  });

  final String deviceName;
  final List<DeviceInfo> devices;
  final int onlineCount;
  final int nearbyCount;
  final PairingModel pairing;
  final AppPalette palette;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;

    String statusText;
    if (pairing.reconnecting) {
      statusText = s.t('status.reconnecting');
    } else if (pairing.connected) {
      DeviceInfo? activePeer;
      for (final d in devices) {
        if (d.deviceId == pairing.activePeerId) {
          activePeer = d;
          break;
        }
      }
      statusText = activePeer != null
          ? s.t('home.connectedToOne', {'name': activePeer.deviceName})
          : s.t('status.connected');
    } else if (devices.isEmpty) {
      statusText = s.t('home.notPairedYet');
    } else {
      statusText = s.t('home.notConnected');
    }

    final live = pairing.connected;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: live ? p.paper : p.inkGhost,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: p.ink)),
            ),
          ],
        ),
        if (devices.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _meta(devices.length, s.t('home.statPaired'), p),
              _dot(p),
              _meta(onlineCount, s.t('common.online'), p),
              _dot(p),
              _meta(nearbyCount, s.t('devices.nearby'), p),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dot(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(fontSize: 12, color: p.inkGhost)),
      );

  Widget _meta(int value, String label, AppPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: value > 0 ? p.ink : p.inkGhost)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: p.inkFaint)),
      ],
    );
  }
}

// ===== Device list =====
// This device's own row, then a "Paired" section, then a "Nearby"
// section for unpaired mDNS advertisers -- the same grouped-card,
// hairline-row language desktop's HomePanel uses (T-desktop-home,
// §2.4), replacing the former constellation/orbit view. Paired rows
// open the same action sheet a tapped star used to; nearby rows pair
// directly, same as before.

class _HomeDeviceList extends StatelessWidget {
  const _HomeDeviceList({
    required this.deviceName,
    required this.paired,
    required this.pairable,
    required this.palette,
    required this.strings,
    required this.onTapPaired,
    required this.onTapNearby,
  });

  final String deviceName;
  final List<DeviceInfo> paired;
  final List<NearbyDevice> pairable;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<DeviceInfo> onTapPaired;
  final ValueChanged<NearbyDevice> onTapNearby;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    final name = deviceName.isEmpty ? s.t('status.thisDevice') : deviceName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _DeviceAvatar(name: name, online: true, palette: p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    Text(s.t('status.thisDevice'),
                        style: TextStyle(fontSize: 12, color: p.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (paired.isNotEmpty) ...[
          const SizedBox(height: 18),
          Eyebrow(s.t('home.paired')),
          const SizedBox(height: 8),
          _ListCard(
            palette: p,
            children: [
              for (final d in paired)
                _PairedRow(device: d, palette: p, strings: s, onTap: onTapPaired),
            ],
          ),
        ],
        if (pairable.isNotEmpty) ...[
          const SizedBox(height: 18),
          Eyebrow(s.t('devices.nearby')),
          const SizedBox(height: 8),
          _ListCard(
            palette: p,
            children: [
              for (final d in pairable)
                _NearbyRow(device: d, palette: p, strings: s, onTap: onTapNearby),
            ],
          ),
        ],
        if (paired.isEmpty && pairable.isEmpty) ...[
          const SizedBox(height: 12),
          EmptyState(
            icon: Icons.devices_other_outlined,
            title: s.t('devices.emptyTitle'),
            hint: s.t('devices.emptyHint'),
          ),
        ],
      ],
    );
  }
}

/// Rounded card that clips its children so per-row [InkWell] ripples
/// stay within the card's own corner radius, with a hairline divider
/// between rows -- the mobile equivalent of desktop's `card`/`card-hover`
/// utility classes.
class _ListCard extends StatelessWidget {
  const _ListCard({required this.palette, required this.children});
  final AppPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i != 0) Divider(color: p.line, height: 1),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({required this.name, this.online, required this.palette});
  final String name;
  final bool? online;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surfaceOverlay,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.line),
          ),
          child: Text(monogram(name),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.inkMuted)),
        ),
        if (online != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: online! ? p.paper : p.inkGhost,
                shape: BoxShape.circle,
                border: Border.all(color: p.surfaceRaised, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _PairedRow extends StatelessWidget {
  const _PairedRow({
    required this.device,
    required this.palette,
    required this.strings,
    required this.onTap,
  });
  final DeviceInfo device;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<DeviceInfo> onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              _DeviceAvatar(name: device.deviceName, online: device.online, palette: p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(platformIcon(device.platform),
                            size: 14, color: p.inkFaint),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(device.deviceName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: p.ink)),
                        ),
                      ],
                    ),
                    Text(
                        device.online
                            ? s.t('devices.onlineNow')
                            : s.t('common.offline'),
                        style: TextStyle(fontSize: 12, color: p.inkFaint)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: device.online ? p.selectedFill : p.surfaceOverlay,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: device.online ? p.selectedBorder : p.line),
                ),
                child: Text(
                  device.online ? s.t('common.online') : s.t('common.offline'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: device.online ? p.ink : p.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({
    required this.device,
    required this.palette,
    required this.strings,
    required this.onTap,
  });
  final NearbyDevice device;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<NearbyDevice> onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              _DeviceAvatar(name: device.deviceName, palette: p),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Icon(platformIcon(device.platform),
                        size: 14, color: p.inkFaint),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(device.deviceName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: p.ink)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: p.selectedFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: p.selectedBorder),
                ),
                child: Text(
                  s.t('common.pair'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Receiving (discoverable) card =====

/// Home-screen control making the inbound server's state impossible to
/// miss: whether this device can be discovered, paired into, and receive
/// files. Receiving is the "service" a peer needs running to reach this
/// device, so surfacing it here (not just buried in Settings) is what
/// keeps "why can't the other device see me / send me a file" from being
/// a mystery.
class _ReceivingCard extends StatelessWidget {
  const _ReceivingCard({
    required this.enabled,
    required this.palette,
    required this.strings,
    required this.onChanged,
  });

  final bool enabled;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: enabled ? Colors.white.withValues(alpha: 0.04) : p.surface,
        border: Border.all(color: enabled ? p.lineStrong : p.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: enabled
                  ? Colors.white.withValues(alpha: 0.06)
                  : p.surfaceOverlay,
              border: Border.all(color: p.line),
            ),
            child: Icon(
              enabled ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              size: 19,
              color: enabled ? p.ink : p.inkFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('home.receivingTitle'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: p.ink)),
                const SizedBox(height: 2),
                Text(
                    enabled
                        ? s.t('home.receivingOnHint')
                        : s.t('home.receivingOffHint'),
                    style: TextStyle(
                        fontSize: 12, height: 1.25, color: p.inkFaint)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: Colors.black,
            activeTrackColor: p.paper,
            inactiveThumbColor: p.inkFaint,
            inactiveTrackColor: p.surfaceOverlay,
            trackOutlineColor: WidgetStatePropertyAll(p.line),
          ),
        ],
      ),
    );
  }
}

// ===== Quick Actions =====

class _QuickAction {
  const _QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.disabled = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.connected,
    required this.onlineCount,
    required this.palette,
    required this.strings,
    this.onNavigateTab,
  });

  final bool connected;
  final int onlineCount;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<int>? onNavigateTab;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;

    // Only 4 cards: send-file/clipboard/remote-input/settings each jump
    // to a real, already-implemented tab in AppShell. A "notifications"
    // card and a "doctor" (connection diagnostics) card were deliberately
    // left out -- neither has a mobile screen backing it (notifications
    // forwarding isn't implemented on mobile at all, and the
    // connection-doctor panel is desktop-only, tracked separately as
    // T-606) -- so no visible action here is ever a dead no-op (T-106).
    final actions = <_QuickAction>[
      _QuickAction(
        id: 'send-file',
        label: s.t('transfers.sendFile'),
        icon: Icons.send,
        onTap: () => onNavigateTab?.call(ShellTab.transfers),
        disabled: onlineCount == 0,
      ),
      _QuickAction(
        id: 'clipboard',
        label: s.t('clipboard.history'),
        icon: Icons.content_paste,
        onTap: () => onNavigateTab?.call(ShellTab.clipboard),
      ),
      _QuickAction(
        id: 'remote-input',
        label: s.t('input.eyebrow'),
        icon: Icons.mouse,
        onTap: () => onNavigateTab?.call(ShellTab.input),
        disabled: !connected,
      ),
      _QuickAction(
        id: 'settings',
        label: s.t('nav.settings'),
        icon: Icons.settings,
        onTap: () => onNavigateTab?.call(ShellTab.settings),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.82,
      children: actions.map((action) {
        final disabled = action.disabled;
        return Material(
          color: disabled ? p.surface.withValues(alpha: 0.5) : p.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: disabled ? null : action.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: disabled ? p.line : p.lineStrong),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon,
                      size: 20, color: disabled ? p.inkFaint : p.ink),
                  const SizedBox(height: 6),
                  Text(action.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: disabled ? p.inkFaint : p.ink)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ===== Manual Connect Sheet =====
// The escape hatch for networks where mDNS/multicast is blocked: type the
// peer's address instead of discovering it. Returns (host, port) on
// connect, or null if dismissed. Also shows this device's own address so
// the other side can type it in the reverse direction.

class ManualConnectSheet extends StatefulWidget {
  const ManualConnectSheet({super.key});

  static Future<(String, int)?> show(BuildContext context) {
    return showModalBottomSheet<(String, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ManualConnectSheet(),
    );
  }

  @override
  State<ManualConnectSheet> createState() => _ManualConnectSheetState();
}

class _ManualConnectSheetState extends State<ManualConnectSheet> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '$kServerPort');
  bool _invalid = false;
  String? _localAddress;

  @override
  void initState() {
    super.initState();
    _resolveLocalAddress();
  }

  Future<void> _resolveLocalAddress() async {
    String? ip;
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      outer:
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            ip = addr.address;
            break outer;
          }
        }
      }
    } catch (_) {
      ip = null;
    }
    if (mounted) setState(() => _localAddress = ip);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop((host, port));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.lineStrong)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + safeBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: p.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(s.t('manual.title'),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 4),
            Text(s.t('manual.subtitle'),
                style: TextStyle(fontSize: 13, color: p.inkMuted)),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    p,
                    label: s.t('manual.addressLabel'),
                    controller: _host,
                    hint: '192.168.1.42',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _field(
                    p,
                    label: s.t('manual.portLabel'),
                    controller: _port,
                    keyboardType: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                  ),
                ),
              ],
            ),
            if (_invalid) ...[
              const SizedBox(height: 8),
              Text(s.t('manual.invalid'),
                  style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: p.paper,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(s.t('manual.connect')),
            ),
            const SizedBox(height: 14),
            _YourAddress(address: _localAddress, palette: p, strings: s),
          ],
        ),
      ),
    );
  }

  Widget _field(
    AppPalette p, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10, letterSpacing: 1.2, color: p.inkFaint)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
          onSubmitted: (_) => _submit(),
          style: TextStyle(
              fontSize: 15,
              color: p.ink,
              fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: p.inkGhost),
            isDense: true,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.35),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.lineStrong),
            ),
          ),
        ),
      ],
    );
  }
}

/// This device's own LAN address, shown so the person on the other device
/// can type it in the reverse direction. Tap to copy.
class _YourAddress extends StatelessWidget {
  const _YourAddress(
      {required this.address, required this.palette, required this.strings});
  final String? address;
  final AppPalette palette;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    final known = address != null;
    final value = known ? '$address:$kServerPort' : s.t('manual.yourAddressUnknown');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: known
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              HapticFeedback.selectionClick();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('manual.yourAddress').toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, letterSpacing: 1.2, color: p.inkFaint)),
                  const SizedBox(height: 3),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          color: known ? p.ink : p.inkFaint,
                          fontFeatures:
                              const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            if (known) Icon(Icons.copy_rounded, size: 16, color: p.inkFaint),
          ],
        ),
      ),
    );
  }
}

// ===== Shared Helpers =====

String monogram(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}
