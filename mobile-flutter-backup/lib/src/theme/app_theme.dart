import 'package:flutter/material.dart';

/// Monochrome black/grey design system, mirroring the desktop app's
/// tokens (see desktop/tailwind.config.js). Three dark theme variants;
/// no blue/purple/gold anywhere. A single near-white is the accent.
enum ThemeId { charcoal, onyx, graphite }

extension ThemeIdX on ThemeId {
  String get id => name;

  static ThemeId fromId(String? value) {
    return ThemeId.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ThemeId.charcoal,
    );
  }
}

/// The full set of monochrome shade tokens for one theme.
@immutable
class AppPalette {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceHover,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkGhost,
    required this.paper,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color surfaceHover;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color inkGhost;
  final Color paper;

  // Constant across themes.
  Color get line => Colors.white.withValues(alpha: 0.08);
  Color get lineStrong => Colors.white.withValues(alpha: 0.14);
  Color get lineFaint => Colors.white.withValues(alpha: 0.05);
  Color get danger => const Color(0xFFE0575B);

  // Selected-state tokens, so selection emphasis is theme-driven and
  // consistent instead of ad-hoc white overlays scattered per screen.
  Color get selectedFill => Colors.white.withValues(alpha: 0.05);
  Color get selectedBorder => Colors.white.withValues(alpha: 0.20);

  static const AppPalette charcoal = AppPalette(
    canvas: Color(0xFF08080A),
    surface: Color(0xFF101012),
    surfaceRaised: Color(0xFF161619),
    surfaceOverlay: Color(0xFF1C1C20),
    surfaceHover: Color(0xFF222227),
    ink: Color(0xFFF2F2F3),
    inkMuted: Color(0xFFA2A2AB),
    inkFaint: Color(0xFF6D6D77),
    inkGhost: Color(0xFF4A4A52),
    paper: Color(0xFFFAFAFA),
  );

  static const AppPalette onyx = AppPalette(
    canvas: Color(0xFF000000),
    surface: Color(0xFF09090B),
    surfaceRaised: Color(0xFF101012),
    surfaceOverlay: Color(0xFF17171A),
    surfaceHover: Color(0xFF1F1F23),
    ink: Color(0xFFF5F5F6),
    inkMuted: Color(0xFFA0A0A8),
    inkFaint: Color(0xFF686872),
    inkGhost: Color(0xFF44444C),
    paper: Color(0xFFFFFFFF),
  );

  static const AppPalette graphite = AppPalette(
    canvas: Color(0xFF0F0F13),
    surface: Color(0xFF18181E),
    surfaceRaised: Color(0xFF202027),
    surfaceOverlay: Color(0xFF28282F),
    surfaceHover: Color(0xFF32323B),
    ink: Color(0xFFECECF0),
    inkMuted: Color(0xFFA8A8B2),
    inkFaint: Color(0xFF767682),
    inkGhost: Color(0xFF545460),
    paper: Color(0xFFF8F8FA),
  );

  static AppPalette of(ThemeId id) {
    switch (id) {
      case ThemeId.charcoal:
        return charcoal;
      case ThemeId.onyx:
        return onyx;
      case ThemeId.graphite:
        return graphite;
    }
  }
}

/// Makes the active palette available through the widget tree via
/// `AppPalette p = context.palette;`.
class AppPaletteScope extends InheritedWidget {
  const AppPaletteScope(
      {super.key, required this.palette, required super.child});

  final AppPalette palette;

  static AppPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppPaletteScope>();
    assert(scope != null, 'AppPaletteScope missing from the widget tree');
    return scope!.palette;
  }

  @override
  bool updateShouldNotify(AppPaletteScope oldWidget) =>
      palette != oldWidget.palette;
}

extension PaletteContext on BuildContext {
  AppPalette get palette => AppPaletteScope.of(this);
}

/// Builds a Material dark [ThemeData] from a palette so standard widgets
/// (text, dividers, inputs) inherit the monochrome look.
ThemeData buildTheme(AppPalette p) {
  const fontFamily = null; // system font; deliberately not Inter.
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    colorScheme: ColorScheme.dark(
      surface: p.surface,
      onSurface: p.ink,
      primary: p.paper,
      onPrimary: Colors.black,
      secondary: p.inkMuted,
      error: p.danger,
      outline: p.lineStrong,
    ),
    dividerColor: p.line,
    // A subtle monochrome ripple. NOT InkSparkle: its fragment shader
    // renders as a solid white fill under Android's Impeller renderer
    // (flutter/flutter#126417), so pressing/holding any InkWell -- the
    // bottom nav, the long-press action sheet -- flashed the area pure
    // white ("ekrana basili tutunca bembeyaz oluyor").
    splashFactory: InkRipple.splashFactory,
    splashColor: Colors.white.withValues(alpha: 0.06),
    highlightColor: Colors.white.withValues(alpha: 0.04),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    iconTheme: IconThemeData(color: p.inkMuted),
  );
}
