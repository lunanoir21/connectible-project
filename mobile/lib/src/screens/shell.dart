import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/pairing_manager.dart';
import '../state/pairing_model.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/responder_pairing_sheet.dart';
import 'clipboard_screen.dart';
import 'home_screen.dart';
import 'remote_input_screen.dart';
import 'settings_screen.dart';
import 'transfers_screen.dart';

/// Top-level shell: a monochrome top bar + bottom navigation between the
/// five mobile sections. The device list lives inside Home (the radar),
/// so the bottom bar stays to five tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // Drives a short fade + rise each time the visible tab changes. The
  // IndexedStack below keeps every screen alive (so the radar controller
  // and scroll positions survive), while this makes the switch feel
  // deliberate instead of an instant hard cut.
  late final AnimationController _switch;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  // Listens for a desktop peer initiating pairing to this phone, and
  // shows the responder PIN sheet. Guarded so only one shows at a time.
  StreamSubscription<PairingRequestedEvent>? _pairingSub;
  bool _showingPairing = false;

  static const _titles = [
    'nav.home',
    'nav.clipboard',
    'nav.transfers',
    'nav.input',
    'nav.settings'
  ];

  /// Rebuilt (not `const`) because HomeScreen needs a live callback to
  /// switch tabs from its Actions cards; order must match ShellTab's
  /// indices in home_screen.dart.
  List<Widget> get _screens => [
        HomeScreen(onNavigateTab: _select),
        const ClipboardScreen(),
        const TransfersScreen(),
        const RemoteInputScreen(),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    _switch = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260))
      ..value = 1;
    final curve = CurvedAnimation(parent: _switch, curve: Curves.easeOutCubic);
    _fade = curve;
    _slide = Tween<Offset>(begin: const Offset(0, 0.018), end: Offset.zero)
        .animate(curve);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pairingSub = context
          .read<PairingModel>()
          .incomingPairings
          .listen(_onIncomingPairing);
    });
  }

  Future<void> _onIncomingPairing(PairingRequestedEvent e) async {
    if (_showingPairing || !mounted) return;
    _showingPairing = true;
    await ResponderPairingSheet.show(
      context,
      requesterDeviceId: e.requesterDeviceId,
      requesterDeviceName: e.requesterDeviceName,
      pinCode: e.pinCode,
      pinExpiresAtMs: e.pinExpiresAtMs,
    );
    _showingPairing = false;
  }

  @override
  void dispose() {
    _pairingSub?.cancel();
    _switch.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _switch.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final model = context.watch<PairingModel>();
    final connected = model.connected;
    final reconnecting = model.reconnecting;

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(s.t(_titles[_index]),
                      key: const Key('shellAppBarTitle'),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                          letterSpacing: -0.3)),
                  const Spacer(),
                  _ConnChip(connected: connected, reconnecting: reconnecting),
                ],
              ),
            ),
          ),
        ),
      ),
      // Guard screen content against left/right display cutouts in
      // landscape; the app bar and bottom nav manage their own insets.
      body: SafeArea(
        top: false,
        bottom: false,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: IndexedStack(index: _index, children: _screens),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            color: p.surface, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavItem(
                    icon: Icons.radar_outlined,
                    label: s.t('nav.home'),
                    active: _index == 0,
                    onTap: () => _select(0)),
                _NavItem(
                    icon: Icons.content_paste_outlined,
                    label: s.t('nav.clipboard'),
                    active: _index == 1,
                    onTap: () => _select(1)),
                _NavItem(
                    icon: Icons.swap_vert,
                    label: s.t('nav.transfers'),
                    active: _index == 2,
                    onTap: () => _select(2)),
                _NavItem(
                    icon: Icons.mouse_outlined,
                    label: s.t('nav.input'),
                    active: _index == 3,
                    onTap: () => _select(3)),
                _NavItem(
                    icon: Icons.settings_outlined,
                    label: s.t('nav.settings'),
                    active: _index == 4,
                    onTap: () => _select(4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const dur = Duration(milliseconds: 220);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashFactory: NoSplash.splashFactory,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active items get a soft pill behind the icon that fades and
            // eases in, and the icon lerps colour + scales up slightly, so
            // switching tabs reads as motion rather than a hard toggle.
            AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: active ? p.surfaceRaised : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? p.line : Colors.transparent),
              ),
              child: AnimatedScale(
                duration: dur,
                curve: Curves.easeOutCubic,
                scale: active ? 1.0 : 0.9,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: active ? 1 : 0),
                  duration: dur,
                  curve: Curves.easeOut,
                  builder: (_, t, __) => Icon(icon,
                      size: 22, color: Color.lerp(p.inkFaint, p.ink, t)),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: dur,
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 10,
                color: active ? p.ink : p.inkFaint,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.connected, required this.reconnecting});
  final bool connected;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final label = connected
        ? s.t('status.connected')
        : reconnecting
            ? s.t('status.reconnecting')
            : s.t('status.connecting');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A steady dot when connected, a pulsing one while retrying, and
          // a dim one before the first connect.
          reconnecting
              ? _PulsingDot(color: p.paper)
              : Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: connected ? p.paper : p.inkGhost,
                      shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: p.inkMuted)),
        ],
      ),
    );
  }
}

/// A small dot that softly pulses, signalling active ret/re-connection.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
