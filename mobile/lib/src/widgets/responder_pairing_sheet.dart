import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/device_list_model.dart';
import '../theme/app_theme.dart';

/// Bottom sheet shown when a *remote* peer (e.g. a desktop) initiates
/// pairing to this phone: it displays the 6-digit PIN the local user
/// reads out to the peer, with a draining countdown. It closes itself
/// when pairing completes (the peer entered the code) or the code
/// expires. This is the responder counterpart to [PairingSheet].
class ResponderPairingSheet extends StatefulWidget {
  const ResponderPairingSheet({
    super.key,
    required this.requesterDeviceId,
    required this.requesterDeviceName,
    required this.pinCode,
    required this.pinExpiresAtMs,
  });

  final String requesterDeviceId;
  final String requesterDeviceName;
  final String pinCode;
  final int pinExpiresAtMs;

  static Future<void> show(
    BuildContext context, {
    required String requesterDeviceId,
    required String requesterDeviceName,
    required String pinCode,
    required int pinExpiresAtMs,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResponderPairingSheet(
        requesterDeviceId: requesterDeviceId,
        requesterDeviceName: requesterDeviceName,
        pinCode: pinCode,
        pinExpiresAtMs: pinExpiresAtMs,
      ),
    );
  }

  @override
  State<ResponderPairingSheet> createState() => _ResponderPairingSheetState();
}

class _ResponderPairingSheetState extends State<ResponderPairingSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown;
  late final int _windowMs;
  bool _expired = false;
  bool _success = false;

  /// Below this many seconds remaining, the countdown shifts to the
  /// palette's danger color as a purposeful "hurry up" affordance
  /// (T-703), mirroring [PairingSheet]'s requester-side countdown.
  static const int _urgentThresholdSeconds = 10;

  @override
  void initState() {
    super.initState();
    final msLeft =
        (widget.pinExpiresAtMs - DateTime.now().millisecondsSinceEpoch)
            .clamp(0, 60000);
    _windowMs = msLeft == 0 ? 1 : msLeft;
    _countdown = AnimationController(
        vsync: this, duration: Duration(milliseconds: _windowMs), value: 1)
      ..reverse()
      ..addStatusListener((s) {
        if (s == AnimationStatus.dismissed && mounted && !_success) {
          setState(() => _expired = true);
        }
      });
    if (msLeft == 0) _expired = true;
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  void _closeSoon() {
    Future<void>.delayed(const Duration(milliseconds: 820), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    // Auto-detect success: the peer completing ConfirmPin adds it to the
    // paired-device store, which surfaces in DeviceListModel.devices.
    final paired = context
        .watch<DeviceListModel>()
        .devices
        .any((d) => d.deviceId == widget.requesterDeviceId);
    if (paired && !_success) {
      _success = true;
      _closeSoon();
    }

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.lineStrong)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + safeBottom),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _success ? _successView(p, s) : _buildBody(p, s),
      ),
    );
  }

  Widget _buildBody(AppPalette p, AppStrings s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: p.lineStrong, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Text(s.t('pairing.incomingTitle'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
        const SizedBox(height: 4),
        Text(s.t('pairing.incomingSub', {'name': widget.requesterDeviceName}),
            style: TextStyle(fontSize: 13, color: p.inkMuted)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.pinCode.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _PinDigit(digit: widget.pinCode[i], palette: p, dim: _expired),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(s.t('pairing.enterOnOther', {'name': widget.requesterDeviceName}),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.inkFaint)),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _countdown,
          builder: (context, _) {
            final fraction = _countdown.value;
            if (fraction <= 0) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(s.t('pairing.timedOut'),
                    style: TextStyle(
                        color: p.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              );
            }
            final remaining = (_windowMs * fraction / 1000).ceil();
            final urgent = remaining <= _urgentThresholdSeconds;
            final barColor = urgent ? p.danger : p.paper;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scoped implicit transition: only re-animates when
                // `urgent` flips, not on every 60fps countdown tick.
                AnimatedDefaultTextStyle(
                  key: const Key('pairingCountdownLabel'),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  style: TextStyle(
                      color: urgent ? p.danger : p.inkFaint, fontSize: 11),
                  child: Text(s.t('pairing.expiresIn', {'n': remaining})),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(begin: barColor, end: barColor),
                    duration: const Duration(milliseconds: 260),
                    builder: (context, color, _) => LinearProgressIndicator(
                      value: fraction,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(color ?? barColor),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _successView(AppPalette p, AppStrings s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Transform.scale(
            scale: 0.4 + 0.6 * t.clamp(0.0, 1.0),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.paper, shape: BoxShape.circle),
            child:
                const Icon(Icons.check_rounded, size: 34, color: Colors.black),
          ),
        ),
        const SizedBox(height: 16),
        Text(s.t('pairing.pairedTitle'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
        const SizedBox(height: 4),
        Text(s.t('pairing.pairedSub'),
            style: TextStyle(fontSize: 13, color: p.inkMuted)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PinDigit extends StatelessWidget {
  const _PinDigit(
      {required this.digit, required this.palette, required this.dim});
  final String digit;
  final AppPalette palette;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: 44,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.lineStrong),
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: dim ? p.inkFaint : p.ink,
        ),
      ),
    );
  }
}
