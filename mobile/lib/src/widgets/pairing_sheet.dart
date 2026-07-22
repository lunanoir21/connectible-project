import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/pairing_model.dart';
import '../theme/app_theme.dart';

/// Bottom sheet where the user types the 6-digit PIN shown on the
/// computer's screen (T-045). Animated per-digit cells over a hidden
/// field, a smoothly draining countdown, a shake + haptic on a rejected
/// code, and a success beat before it closes.
class PairingSheet extends StatefulWidget {
  const PairingSheet(
      {super.key, required this.deviceName, required this.pinExpiresAtMs});

  final String deviceName;
  final int pinExpiresAtMs;

  static Future<void> show(BuildContext context,
      {required String deviceName, required int pinExpiresAtMs}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          PairingSheet(deviceName: deviceName, pinExpiresAtMs: pinExpiresAtMs),
    );
  }

  @override
  State<PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<PairingSheet>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  late final AnimationController _countdown;
  late final AnimationController _shake;

  late final int _windowMs; // full PIN lifetime, for the progress fraction
  bool _submitting = false;
  bool _success = false;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final msLeft =
        (widget.pinExpiresAtMs - DateTime.now().millisecondsSinceEpoch)
            .clamp(0, 60000);
    _windowMs = msLeft == 0 ? 1 : msLeft;

    // Reversing 1 -> 0 over the remaining time gives a continuous drain
    // (60fps) instead of the old 500ms stepped ticker.
    _countdown = AnimationController(
        vsync: this, duration: Duration(milliseconds: _windowMs), value: 1)
      ..reverse()
      ..addStatusListener((s) {
        if (s == AnimationStatus.dismissed && mounted) {
          setState(() => _expired = true);
        }
      });

    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));

    if (msLeft == 0) _expired = true;
    // Focus after the sheet finishes presenting so the keyboard rises
    // smoothly with the sheet rather than fighting its entrance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  bool get _canSubmit =>
      RegExp(r'^\d{6}$').hasMatch(_controller.text) &&
      !_expired &&
      !_submitting;

  void _onChanged(String value) {
    setState(() {});
    if (value.isNotEmpty) HapticFeedback.selectionClick();
    if (RegExp(r'^\d{6}$').hasMatch(value) && !_submitting && !_expired) {
      _submit();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    _focus.unfocus();
    final ok = await context.read<PairingModel>().confirmPin(_controller.text);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() => _success = true);
      await Future<void>.delayed(const Duration(milliseconds: 780));
      if (mounted) Navigator.of(context).pop();
    } else {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _submitting = false;
        _error = context.strings.t('pairing.incorrectPin');
        _controller.clear();
      });
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    _shake.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
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
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + safeBottom),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _success
              ? _SuccessView(palette: p, strings: s)
              : _buildForm(p, s),
        ),
      ),
    );
  }

  Widget _buildForm(AppPalette p, AppStrings s) {
    return Column(
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
        Center(child: _LinkGlyph(paired: false, palette: p)),
        const SizedBox(height: 16),
        Text(s.t('pairing.title'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
        const SizedBox(height: 4),
        Text(s.t('pairing.subtitle', {'name': widget.deviceName}),
            style: TextStyle(fontSize: 13, color: p.inkMuted)),
        const SizedBox(height: 18),

        // Hidden field carries the value + keyboard; the cells are the
        // visual layer. Tapping the cells focuses the field.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    enabled: !_expired && !_submitting,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    onChanged: _onChanged,
                    showCursor: false,
                    style: const TextStyle(color: Colors.transparent),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  // Damped horizontal wobble that settles to rest.
                  final dx =
                      sin(_shake.value * pi * 5) * (1 - _shake.value) * 9;
                  return Transform.translate(
                      offset: Offset(dx, 0), child: child);
                },
                child: _PinCells(
                  value: _controller.text,
                  error: _error != null,
                  active: !_expired && !_submitting,
                  palette: p,
                ),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        _Countdown(
            controller: _countdown,
            windowMs: _windowMs,
            palette: p,
            strings: s),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: p.paper,
            foregroundColor: Colors.black,
            disabledBackgroundColor: p.surfaceHover,
            disabledForegroundColor: p.inkFaint,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _submitting
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(p.inkFaint)),
                )
              : Text(s.t('common.pair')),
        ),
      ],
    );
  }
}

/// The pairing hero: two nodes -- this phone and the peer -- with a tie
/// between them, echoing the home constellation. While connecting, a
/// heartbeat travels the tie and both nodes wear a breathing halo; once
/// [paired] the tie locks solid and the peer resolves into a check. The
/// ambient loop stops under reduced motion.
class _LinkGlyph extends StatefulWidget {
  const _LinkGlyph({required this.paired, required this.palette});
  final bool paired;
  final AppPalette palette;

  @override
  State<_LinkGlyph> createState() => _LinkGlyphState();
}

class _LinkGlyphState extends State<_LinkGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduce && !widget.paired && !_started) {
      _started = true;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _LinkGlyphPainter(
            paired: widget.paired,
            t: _c.value,
            palette: widget.palette,
          ),
        ),
      ),
    );
  }
}

class _LinkGlyphPainter extends CustomPainter {
  _LinkGlyphPainter(
      {required this.paired, required this.t, required this.palette});
  final bool paired;
  final double t; // 0..1 looping
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final a = Offset(size.width * 0.18, cy); // this phone
    final b = Offset(size.width * 0.82, cy); // the peer
    const nodeR = 6.0;

    // Tie.
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = Colors.white.withValues(alpha: paired ? 0.5 : 0.16)
        ..strokeWidth = paired ? 2 : 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Heartbeat traveling the tie while connecting.
    if (!paired) {
      final frac = t;
      final at = Offset.lerp(a, b, frac)!;
      final fade = sin(frac * pi);
      canvas.drawCircle(
          at,
          3.2,
          Paint()
            ..color = palette.paper.withValues(alpha: 0.9 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(
          at, 2, Paint()..color = palette.paper.withValues(alpha: fade));
    }

    // This phone -- always lit, with a breathing halo while connecting.
    if (!paired) {
      canvas.drawCircle(
          a,
          nodeR + nodeR * 1.2 * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = palette.paper.withValues(alpha: 0.5 * (1 - t)));
    }
    canvas.drawCircle(
        a,
        nodeR + 2,
        Paint()
          ..color = palette.paper.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(a, nodeR, Paint()..color = palette.paper);

    // The peer.
    if (paired) {
      canvas.drawCircle(
          b,
          nodeR + 3,
          Paint()
            ..color = palette.paper.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(b, nodeR + 2, Paint()..color = palette.paper);
      final check = Path()
        ..moveTo(b.dx - 4, b.dy)
        ..lineTo(b.dx - 1, b.dy + 3)
        ..lineTo(b.dx + 4, b.dy - 3);
      canvas.drawPath(
          check,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.black);
    } else {
      final phase = (t + 0.5) % 1.0;
      canvas.drawCircle(
          b,
          nodeR + nodeR * 1.2 * phase,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = palette.paper.withValues(alpha: 0.4 * (1 - phase)));
      canvas.drawCircle(b, nodeR, Paint()..color = palette.canvas);
      canvas.drawCircle(
          b,
          nodeR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: 0.28));
    }
  }

  @override
  bool shouldRepaint(_LinkGlyphPainter old) =>
      old.t != t || old.paired != paired || old.palette != palette;
}

/// The six PIN cells. Filled cells pop their digit in; the next empty
/// cell shows a blinking caret; a rejected code tints every border red.
class _PinCells extends StatelessWidget {
  const _PinCells(
      {required this.value,
      required this.error,
      required this.active,
      required this.palette});
  final String value;
  final bool error;
  final bool active;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 6; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _PinCell(
              digit: i < value.length ? value[i] : null,
              active: active && i == value.length,
              error: error,
              palette: palette,
            ),
          ),
        ],
      ],
    );
  }
}

class _PinCell extends StatelessWidget {
  const _PinCell(
      {required this.digit,
      required this.active,
      required this.error,
      required this.palette});
  final String? digit;
  final bool active;
  final bool error;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final filled = digit != null;
    final Color border = error
        ? p.danger
        : active
            ? Colors.white.withValues(alpha: 0.45)
            : filled
                ? p.lineStrong
                : p.line;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: active || error ? 1.6 : 1),
      ),
      child: filled
          ? TweenAnimationBuilder<double>(
              key: ValueKey(digit),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (_, t, __) => Transform.scale(
                scale: 0.5 + 0.5 * t.clamp(0.0, 1.0),
                child: Opacity(opacity: t.clamp(0.0, 1.0), child: child(p)),
              ),
            )
          : (active ? _Caret(color: p.ink) : const SizedBox.shrink()),
    );
  }

  Widget child(AppPalette p) => Text(digit!,
      style:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: p.ink));
}

/// A blinking caret for the active empty cell.
class _Caret extends StatefulWidget {
  const _Caret({required this.color});
  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // Square wave: solid, then off, then on -- a classic caret blink.
      opacity: _c.drive(TweenSequence<double>([
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 1),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 1),
      ])),
      child: Container(width: 2, height: 24, color: widget.color),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown(
      {required this.controller,
      required this.windowMs,
      required this.palette,
      required this.strings});
  final AnimationController controller;
  final int windowMs;
  final AppPalette palette;
  final AppStrings strings;

  /// Below this many seconds remaining, the countdown shifts to the
  /// palette's danger color as a purposeful "hurry up" affordance
  /// (T-703) instead of staying neutral until the code times out.
  static const int urgentThresholdSeconds = 10;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final fraction = controller.value; // 1 -> 0
        final expired = fraction <= 0;
        if (expired) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(strings.t('pairing.timedOut'),
                style: TextStyle(
                    color: p.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          );
        }
        final remaining = (windowMs * fraction / 1000).ceil();
        final urgent = remaining <= urgentThresholdSeconds;
        final barColor = urgent ? p.danger : p.paper;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Implicit color tween on just this label, scoped so
                // the 60fps countdown ticker above doesn't force a
                // fresh transition every frame -- AnimatedDefaultTextStyle
                // only animates when the resolved TextStyle actually
                // changes (i.e. the moment `urgent` flips).
                AnimatedDefaultTextStyle(
                  key: const Key('pairingCountdownLabel'),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  style: TextStyle(
                      color: urgent ? p.danger : p.inkFaint, fontSize: 11),
                  child: Text(strings.t('pairing.expiresIn', {'n': remaining})),
                ),
              ],
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
    );
  }
}

/// Shown briefly after a verified PIN: a checkmark that pops in.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.palette, required this.strings});
  final AppPalette palette;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Transform.scale(
            scale: 0.6 + 0.4 * t.clamp(0.0, 1.0),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
          // The tie locks and the peer resolves into a check -- the same
          // linking glyph the form opened with, now completed.
          child: _LinkGlyph(paired: true, palette: p),
        ),
        const SizedBox(height: 16),
        Text(strings.t('pairing.pairedTitle'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
        const SizedBox(height: 4),
        Text(strings.t('pairing.pairedSub'),
            style: TextStyle(fontSize: 13, color: p.inkMuted)),
        const SizedBox(height: 12),
      ],
    );
  }
}
