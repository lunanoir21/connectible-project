import 'dart:io';
import 'dart:math' as math;

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
import '../widgets/ui.dart' show platformIcon;

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<DeviceListModel>().startDiscovery());
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
    final model = context.read<PairingModel>();
    final ok = await model.startPair(device);
    if (!mounted) return;
    final pending = model.pendingPairing;
    if (ok && pending != null) {
      await PairingSheet.show(context,
          deviceName: device.deviceName,
          pinExpiresAtMs: pending.pinExpiresAtMs);
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
          ConstellationView(
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
            child: TextButton.icon(
              onPressed: () => _openManualConnect(context),
              icon: Icon(Icons.link, size: 16, color: p.inkMuted),
              label: Text(s.t('home.connectByAddress'),
                  style: TextStyle(fontSize: 13, color: p.inkMuted)),
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

// ===== Constellation =====
// The home's signature. This phone sits at the center; every peer is a
// star held on an orbit by a tie back to you. State is legible in the
// structure: paired peers ride the inner orbit, nearby-but-unpaired ones
// the looser outer orbit; the tie carries the live reading -- a solid
// welded line and a lit star for an online peer, a thin line and a
// hollow star when offline, a dashed detached tie for a device merely in
// range. Motion is one orchestrated page-load (center -> ties draw out
// -> stars land), then two quiet ambient loops: a heartbeat traveling
// each live tie, and a halo breathing on live stars. Both loops stop
// when the platform asks for reduced motion.

enum _StarKind { online, offline, nearby }

class _Star {
  const _Star({
    required this.id,
    required this.name,
    required this.kind,
    required this.pos,
    required this.index,
    this.device,
    this.nearby,
  });

  final String id;
  final String name;
  final _StarKind kind;
  final Offset pos;
  final int index;
  final DeviceInfo? device;
  final NearbyDevice? nearby;
}

class ConstellationView extends StatefulWidget {
  const ConstellationView({
    super.key,
    required this.deviceName,
    required this.paired,
    required this.pairable,
    required this.palette,
    required this.strings,
    required this.onTapPaired,
    required this.onTapNearby,
    this.height = 328,
  });

  final String deviceName;
  final List<DeviceInfo> paired;
  final List<NearbyDevice> pairable;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<DeviceInfo> onTapPaired;
  final ValueChanged<NearbyDevice> onTapNearby;
  final double height;

  @override
  State<ConstellationView> createState() => _ConstellationViewState();
}

class _ConstellationViewState extends State<ConstellationView>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1150));
  late final AnimationController _ambient = AnimationController(
      vsync: this, duration: const Duration(seconds: 3));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      // Skip straight to the settled frame and never loop, so a reduced-
      // motion user (and widget tests calling pumpAndSettle) sees a
      // static constellation instead of perpetual animation.
      _entrance.value = 1;
    } else if (!_started) {
      _started = true;
      _entrance.forward();
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
    super.dispose();
  }

  List<_Star> _layout(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rMax = math.min(size.width / 2, size.height / 2) - 34;
    final innerRing = rMax * 0.74;
    final outerRing = rMax;
    final hasPaired = widget.paired.isNotEmpty;

    List<_Star> place<T>(
      List<T> items,
      double ring,
      double startDeg,
      int indexOffset,
      _Star Function(T item, Offset pos, int index) make,
    ) {
      final n = items.length;
      return List<_Star>.generate(n, (i) {
        final step = n > 0 ? 360.0 / n : 0.0;
        final base = n == 1 ? -90.0 : startDeg + i * step;
        final seed = _hashSeed((items[i] as dynamic).deviceId as String);
        final spread = n > 4 ? 8.0 : 15.0;
        final jitterA = ((seed % 1000) / 1000 - 0.5) * spread;
        final jitterR = (((seed >> 10) % 1000) / 1000 - 0.5) * 16;
        final ang = (base + jitterA) * math.pi / 180;
        final rr = ring + jitterR;
        final pos = center + Offset(rr * math.cos(ang), rr * math.sin(ang));
        return make(items[i], pos, indexOffset + i);
      });
    }

    final paired = place<DeviceInfo>(
      widget.paired,
      innerRing,
      -90,
      0,
      (d, pos, index) => _Star(
        id: d.deviceId,
        name: d.deviceName,
        kind: d.online ? _StarKind.online : _StarKind.offline,
        pos: pos,
        index: index,
        device: d,
      ),
    );
    final near = place<NearbyDevice>(
      widget.pairable,
      hasPaired ? outerRing : innerRing,
      -70,
      widget.paired.length,
      (d, pos, index) => _Star(
        id: d.deviceId,
        name: d.deviceName,
        kind: _StarKind.nearby,
        pos: pos,
        index: index,
        nearby: d,
      ),
    );
    return [...paired, ...near];
  }

  void _handleTap(Offset local, List<_Star> stars) {
    _Star? hit;
    double best = 30; // generous touch radius
    for (final star in stars) {
      final d = (star.pos - local).distance;
      if (d < best) {
        best = d;
        hit = star;
      }
    }
    if (hit == null) return;
    if (hit.kind == _StarKind.nearby && hit.nearby != null) {
      widget.onTapNearby(hit.nearby!);
    } else if (hit.device != null) {
      widget.onTapPaired(hit.device!);
    }
  }

  /// A small monochrome platform icon centered on each paired node, faded
  /// in with the entrance sequence. Only paired stars (which carry a real
  /// peer Identity, hence a platform) get one; unknown platforms fall back
  /// to the generic device glyph via [platformIcon].
  List<Widget> _platformBadges(List<_Star> stars) {
    const nodeR = 7.0; // matches _ConstellationPainter._nodeR
    final p = widget.palette;
    final badges = <Widget>[];
    for (final star in stars) {
      final device = star.device;
      if (device == null || star.kind == _StarKind.nearby) continue;
      final online = star.kind == _StarKind.online;
      badges.add(Positioned(
        left: star.pos.dx - nodeR,
        top: star.pos.dy - nodeR,
        width: nodeR * 2,
        height: nodeR * 2,
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) => Opacity(
            opacity: ((_entrance.value - 0.6) / 0.4).clamp(0.0, 1.0),
            child: child,
          ),
          child: Center(
            child: Icon(
              platformIcon(device.platform),
              size: 9,
              // Dark glyph over the light filled online node; a muted light
              // glyph over the dark offline node -- monochrome either way.
              color: online ? p.canvas : p.inkMuted,
            ),
          ),
        ),
      ));
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        final stars = _layout(size);
        final empty = stars.isEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d.localPosition, stars),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_entrance, _ambient]),
                    builder: (context, _) => CustomPaint(
                      painter: _ConstellationPainter(
                        stars: stars,
                        deviceName: widget.deviceName,
                        palette: widget.palette,
                        entrance: Curves.easeOutCubic.transform(_entrance.value),
                        ambient: _ambient.value,
                      ),
                    ),
                  ),
                ),
                // Platform icons over the paired nodes (T-E6). Rendered as
                // real widgets rather than painted glyphs so the icon is
                // findable/accessible; nearby (unpaired) nodes stay bare
                // dashed rings, which keeps "known" vs "discovered" legible.
                ..._platformBadges(stars),
                if (empty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34,
                    child: Column(
                      children: [
                        Text(s.t('devices.emptyTitle'),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: widget.palette.ink)),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(s.t('devices.emptyHint'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: widget.palette.inkFaint)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.stars,
    required this.deviceName,
    required this.palette,
    required this.entrance,
    required this.ambient,
  });

  final List<_Star> stars;
  final String deviceName;
  final AppPalette palette;
  final double entrance; // 0..1 eased, page-load sequence
  final double ambient; // 0..1 looping

  static const double _nodeR = 7;
  static const double _centerR = 27;

  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rMax = math.min(size.width / 2, size.height / 2) - 34;
    final innerRing = rMax * 0.74;
    final outerRing = rMax;
    final anyOnline = stars.any((s) => s.kind == _StarKind.online);
    final anyNearby = stars.any((s) => s.kind == _StarKind.nearby);
    final hasPaired = stars.any((s) => s.kind != _StarKind.nearby);

    _paintField(canvas, size, center, outerRing);

    // Orbit guides.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(center, innerRing, guide);
    if (hasPaired && anyNearby) {
      _dashedCircle(canvas, center, outerRing,
          Colors.white.withValues(alpha: 0.04), 2, 6);
    }

    // Ties.
    for (final star in stars) {
      final tie = _seg(entrance, 0.08 + star.index * 0.05, 0.5 + star.index * 0.05);
      if (star.kind == _StarKind.nearby) {
        _dashedLine(
          canvas,
          center,
          Offset.lerp(center, star.pos, tie)!,
          Colors.white.withValues(alpha: 0.12 * tie),
          1,
          5,
          4,
        );
      } else {
        final live = star.kind == _StarKind.online;
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = live ? 1.6 : 1.0
          ..color = Colors.white
              .withValues(alpha: (live ? 0.28 : 0.08));
        canvas.drawLine(center, Offset.lerp(center, star.pos, tie)!, paint);
      }
    }

    // Heartbeat: a lit dot traveling center -> live star.
    for (final star in stars) {
      if (star.kind != _StarKind.online) continue;
      if (entrance < 0.6) continue;
      final frac = (ambient + star.index * 0.17) % 1.0;
      final at = Offset.lerp(center, star.pos, frac)!;
      final fade = math.sin(frac * math.pi);
      final glow = Paint()
        ..color = palette.paper.withValues(alpha: 0.9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(at, 3.2, glow);
      canvas.drawCircle(
          at, 2.0, Paint()..color = palette.paper.withValues(alpha: fade));
    }

    // Stars.
    for (final star in stars) {
      final pop = _seg(entrance, 0.42 + star.index * 0.05, 0.9 + star.index * 0.04);
      final scale = Curves.easeOutBack.transform(pop);
      if (scale <= 0) continue;
      _paintStar(canvas, star, scale);
      _paintLabel(canvas, star, _seg(entrance, 0.6, 1.0));
    }

    // Center: this device (drawn last, over the tie roots).
    _paintCenter(canvas, center, anyOnline);
  }

  void _paintStar(Canvas canvas, _Star star, double scale) {
    final c = star.pos;
    final r = _nodeR * scale;
    if (star.kind == _StarKind.online) {
      // Halo breathing outward.
      final hp = ambient;
      canvas.drawCircle(
        c,
        _nodeR + _nodeR * 1.2 * hp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.paper.withValues(alpha: 0.5 * (1 - hp)),
      );
      canvas.drawCircle(
          c,
          r + 3,
          Paint()
            ..color = palette.paper.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(c, r, Paint()..color = palette.paper);
    } else if (star.kind == _StarKind.offline) {
      canvas.drawCircle(c, r, Paint()..color = palette.canvas);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: 0.24));
    } else {
      canvas.drawCircle(c, r, Paint()..color = palette.canvas);
      _dashedCircle(canvas, c, r, Colors.white.withValues(alpha: 0.26), 2.5, 2.5,
          strokeWidth: 1.4);
    }
  }

  void _paintLabel(Canvas canvas, _Star star, double opacity) {
    if (opacity <= 0) return;
    final name = star.name.length > 15 ? '${star.name.substring(0, 14)}…' : star.name;
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: palette.inkMuted.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    tp.paint(canvas,
        Offset(star.pos.dx - tp.width / 2, star.pos.dy + _nodeR + 8));
  }

  void _paintCenter(Canvas canvas, Offset center, bool anyOnline) {
    if (anyOnline) {
      final hp = ambient;
      canvas.drawCircle(
        center,
        _centerR + _centerR * 0.35 * hp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.paper.withValues(alpha: 0.4 * (1 - hp)),
      );
    }
    canvas.drawCircle(center, _centerR, Paint()..color = palette.surfaceRaised);
    canvas.drawCircle(
      center,
      _centerR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 0.85,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: _centerR)),
    );
    canvas.drawCircle(
        center,
        _centerR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.16));
    final tp = TextPainter(
      text: TextSpan(
        text: monogram(deviceName.isEmpty ? 'Me' : deviceName),
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: palette.ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _paintField(Canvas canvas, Size size, Offset center, double clearR) {
    // Deterministic faint scatter, twinkling out of phase.
    var seed = 0x9e3779b9;
    double rnd() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    var placed = 0;
    var tries = 0;
    while (placed < 22 && tries < 300) {
      tries++;
      final x = rnd() * size.width;
      final y = rnd() * size.height;
      final p = Offset(x, y);
      if ((p - center).distance < clearR + 22) continue;
      placed++;
      final phase = rnd();
      final tw = (0.1 + 0.32 * (0.5 + 0.5 * math.sin((ambient + phase) * 2 * math.pi)))
          .clamp(0.0, 1.0);
      canvas.drawCircle(p, 0.7 + rnd() * 1.1,
          Paint()..color = palette.inkGhost.withValues(alpha: tw));
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Color color,
      double width, double dash, double gap) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dash, total);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  void _dashedCircle(Canvas canvas, Offset center, double radius, Color color,
      double dash, double gap,
      {double strokeWidth = 1}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final circumference = 2 * math.pi * radius;
    final step = (dash + gap) / radius; // radians
    final dashAngle = dash / radius;
    if (circumference <= 0) return;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        a,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      old.entrance != entrance ||
      old.ambient != ambient ||
      old.stars != stars ||
      old.deviceName != deviceName ||
      old.palette != palette;
}

int _hashSeed(String s) {
  var h = 2166136261;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 16777619) & 0xffffffff;
  }
  return h;
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
