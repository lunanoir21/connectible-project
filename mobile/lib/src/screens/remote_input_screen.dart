import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pairing_model.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

/// X11 keysym values for the non-printable keys this screen sends
/// explicitly (see `proto/connectible.proto`'s `RemoteInputEvent.key_code`
/// comment: "Uses the X11 keysym value"). Printable characters typed into
/// the keyboard field are already sent as their Unicode code unit, which
/// matches the X11 keysym for the whole printable ASCII range.
class _Keysym {
  const _Keysym._();
  static const int backspace = 0xff08;
  static const int tab = 0xff09;
  static const int enter = 0xff0d;
  static const int left = 0xff51;
  static const int up = 0xff52;
  static const int right = 0xff53;
  static const int down = 0xff54;

  /// X11 keysym for function key F[n] (F1 = 0xffbe .. F12 = 0xffc9); the
  /// keysyms are contiguous, so F[n] = F1 + (n - 1).
  static const int f1 = 0xffbe;
  static int fn(int n) => f1 + (n - 1);
}

/// Function keys exposed by the remote keyboard (T-E5): F1 through F12.
const List<int> _functionKeyNumbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// Wire bit flags for `RemoteInputEvent.modifiers` (1=shift, 2=ctrl,
/// 4=alt, 8=meta).
class _ModifierBit {
  const _ModifierBit._();
  static const int shift = 1;
  static const int ctrl = 2;
  static const int alt = 4;
}

/// Touchpad + keyboard remote control (T-048, extended by T-305). Drag
/// moves the pointer (normalized coords), tap = left click, double-tap =
/// double left-click, a two-finger vertical drag emits scroll events, and
/// the keyboard rows add Enter/Backspace/arrow keys (T-E4), Tab and
/// F1-F12 (T-E5) plus sticky Shift/Ctrl/Alt modifiers applied to every
/// key sent while held.
class RemoteInputScreen extends StatefulWidget {
  const RemoteInputScreen({super.key});

  @override
  State<RemoteInputScreen> createState() => _RemoteInputScreenState();
}

class _RemoteInputScreenState extends State<RemoteInputScreen> {
  final FocusNode _keyboardFocus = FocusNode();
  final TextEditingController _keyboardController = TextEditingController();
  Size _padSize = Size.zero;
  Offset? _lastFocalPoint;

  /// Logical pixels of two-finger drag that make up one scroll "tick"
  /// (`RemoteInputEvent.scroll_delta_y` of magnitude 1.0). Emitting whole
  /// ticks rather than a raw per-frame pixel fraction keeps each frame's
  /// delta meaningfully non-zero for backends that operate on integer
  /// scroll units (e.g. a mouse wheel click).
  static const double _scrollPxPerTick = 24.0;
  double _scrollAccumPx = 0;

  bool _shiftOn = false;
  bool _ctrlOn = false;
  bool _altOn = false;

  int get _modifierMask =>
      (_shiftOn ? _ModifierBit.shift : 0) |
      (_ctrlOn ? _ModifierBit.ctrl : 0) |
      (_altOn ? _ModifierBit.alt : 0);

  void _move(PairingModel model, Offset local) {
    if (_padSize.width <= 0 || _padSize.height <= 0) return;
    final x = (local.dx / _padSize.width).clamp(0.0, 1.0);
    final y = (local.dy / _padSize.height).clamp(0.0, 1.0);
    model.sendPointerMove(x, y);
  }

  void _click(PairingModel model, pb.MouseButton button) {
    model.sendMouseButton(button, true);
    model.sendMouseButton(button, false);
  }

  void _doubleClick(PairingModel model, pb.MouseButton button) {
    _click(model, button);
    _click(model, button);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _scrollAccumPx = 0;
  }

  /// [ScaleUpdateDetails.pointerCount] tells one-finger drag (pointer
  /// move) apart from a two-finger gesture (scroll) using a single
  /// recognizer, since `GestureDetector`'s pan and scale callbacks cannot
  /// be registered together.
  void _onScaleUpdate(PairingModel model, ScaleUpdateDetails details) {
    final last = _lastFocalPoint ?? details.localFocalPoint;
    if (details.pointerCount >= 2) {
      _scrollAccumPx += details.localFocalPoint.dy - last.dy;
      while (_scrollAccumPx.abs() >= _scrollPxPerTick) {
        final tick = _scrollAccumPx.isNegative ? -1.0 : 1.0;
        // Natural-scrolling convention: dragging fingers down moves the
        // view down, i.e. the wire contract's negative "scroll down".
        model.sendScroll(0, -tick);
        _scrollAccumPx -= tick * _scrollPxPerTick;
      }
    } else {
      _move(model, details.localFocalPoint);
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  void _sendSpecialKey(PairingModel model, int keysym) {
    model.sendKey(keysym, true, modifiers: _modifierMask);
    model.sendKey(keysym, false, modifiers: _modifierMask);
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    _keyboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final model = context.watch<PairingModel>();

    if (!model.connected) {
      return EmptyState(
          icon: Icons.mouse_outlined,
          title: s.t('input.title'),
          hint: s.t('input.noDevice'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t('input.hint'),
              style: TextStyle(fontSize: 13, height: 1.4, color: p.inkFaint)),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _padSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (d) => _onScaleUpdate(model, d),
                  onTap: () => _click(model, pb.MouseButton.MOUSE_BUTTON_LEFT),
                  onDoubleTap: () =>
                      _doubleClick(model, pb.MouseButton.MOUSE_BUTTON_LEFT),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.line),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.touch_app_outlined,
                        size: 40, color: p.inkGhost),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Btn(
                      label: s.t('input.leftClick'),
                      onTap: () =>
                          _click(model, pb.MouseButton.MOUSE_BUTTON_LEFT))),
              const SizedBox(width: 10),
              Expanded(
                  child: _Btn(
                      label: s.t('input.rightClick'),
                      onTap: () =>
                          _click(model, pb.MouseButton.MOUSE_BUTTON_RIGHT))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _IconBtn(
                  icon: Icons.keyboard_arrow_left,
                  tooltip: s.t('input.arrowLeft'),
                  onTap: () => _sendSpecialKey(model, _Keysym.left),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IconBtn(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: s.t('input.arrowUp'),
                  onTap: () => _sendSpecialKey(model, _Keysym.up),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IconBtn(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: s.t('input.arrowDown'),
                  onTap: () => _sendSpecialKey(model, _Keysym.down),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IconBtn(
                  icon: Icons.keyboard_arrow_right,
                  tooltip: s.t('input.arrowRight'),
                  onTap: () => _sendSpecialKey(model, _Keysym.right),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Btn(
                  label: s.t('input.backspace'),
                  onTap: () => _sendSpecialKey(model, _Keysym.backspace),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Btn(
                  label: s.t('input.enter'),
                  onTap: () => _sendSpecialKey(model, _Keysym.enter),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tab + F1-F12 (T-E5). A Wrap keeps the 13 compact key caps on
          // as many rows as the width allows rather than overflowing.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _KeyCap(
                label: s.t('input.tab'),
                onTap: () => _sendSpecialKey(model, _Keysym.tab),
              ),
              for (final n in _functionKeyNumbers)
                _KeyCap(
                  label: 'F$n',
                  onTap: () => _sendSpecialKey(model, _Keysym.fn(n)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ModifierChip(
                  label: s.t('input.shift'),
                  active: _shiftOn,
                  onTap: () => setState(() => _shiftOn = !_shiftOn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModifierChip(
                  label: s.t('input.ctrl'),
                  active: _ctrlOn,
                  onTap: () => setState(() => _ctrlOn = !_ctrlOn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModifierChip(
                  label: s.t('input.alt'),
                  active: _altOn,
                  onTap: () => setState(() => _altOn = !_altOn),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            focusNode: _keyboardFocus,
            controller: _keyboardController,
            onChanged: (value) {
              // Send each newly typed character as a key press/release,
              // then clear so the field acts as a pass-through key source.
              if (value.isNotEmpty) {
                final code = value.codeUnitAt(value.length - 1);
                model.sendKey(code, true, modifiers: _modifierMask);
                model.sendKey(code, false, modifiers: _modifierMask);
                _keyboardController.clear();
              }
            },
            onSubmitted: (_) => _sendSpecialKey(model, _Keysym.enter),
            style: TextStyle(color: p.ink),
            decoration: InputDecoration(
              hintText: s.t('input.keyboard'),
              hintStyle: TextStyle(color: p.inkGhost),
              prefixIcon: Icon(Icons.keyboard_outlined, color: p.inkMuted),
              filled: true,
              fillColor: p.surfaceRaised,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.lineStrong)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.lineStrong),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14, color: p.ink, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;

  /// Icon-only button, so this is the only thing describing what it does
  /// to a screen reader (or a sighted user who hasn't guessed the icon
  /// yet) -- a bare `GestureDetector` around an `Icon` has no accessible
  /// label at all otherwise.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.lineStrong),
          ),
          child: Icon(icon, size: 20, color: p.ink),
        ),
      ),
    );
  }
}

/// Compact fixed-width key cap used for the Tab + F1-F12 Wrap (T-E5),
/// matching `_Btn`'s monochrome surface/border styling but narrow enough
/// to fit several per row.
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.lineStrong),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, color: p.ink, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Sticky modifier toggle (Shift/Ctrl/Alt): stays highlighted while held
/// "down" and applies its bit to every key sent until toggled off again.
class _ModifierChip extends StatelessWidget {
  const _ModifierChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? p.selectedFill : p.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? p.selectedBorder : p.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? p.ink : p.inkMuted)),
      ),
    );
  }
}
