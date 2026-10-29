import 'package:flutter/material.dart';

import '../models.dart';

class XPalette extends ThemeExtension<XPalette> {
  const XPalette({
    required this.bg,
    required this.glass,
    required this.border,
    required this.accent,
    required this.accent2,
    required this.text,
    required this.dim,
    required this.ok,
    required this.danger,
    required this.blur,
    required this.dark,
  });

  final List<Color> bg;
  final Color glass, border, accent, accent2, text, dim, ok, danger;
  final bool blur, dark;

  Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : const Color(0xFF0B0E13);

  static XPalette of(BuildContext c) => Theme.of(c).extension<XPalette>()!;

  @override
  XPalette copyWith() => this;

  @override
  XPalette lerp(ThemeExtension<XPalette>? other, double t) => other is XPalette ? (t < 0.5 ? this : other) : this;
}

class Accents {
  static const names = {
    AccentId.turquoise: 'Turquoise',
    AccentId.blue: 'Blue',
    AccentId.black: 'Black',
    AccentId.green: 'Green',
    AccentId.pink: 'Pink',
    AccentId.teal: 'Teal',
    AccentId.custom: 'Custom',
  };

  static Color color(AccentId id, Brightness b, int custom) {
    final d = b == Brightness.dark;
    switch (id) {
      case AccentId.turquoise:
        return d ? const Color(0xFF3FB5AD) : const Color(0xFF2A958E);
      case AccentId.blue:
        return d ? const Color(0xFF5B8DEF) : const Color(0xFF3B6FD4);
      case AccentId.black:
        return d ? const Color(0xFFC8D0DA) : const Color(0xFF14181F);
      case AccentId.green:
        return d ? const Color(0xFF4DB47E) : const Color(0xFF2F9660);
      case AccentId.pink:
        return d ? const Color(0xFFE27AA6) : const Color(0xFFC8507F);
      case AccentId.teal:
        return d ? const Color(0xFF1D9AAA) : const Color(0xFF11788A);
      case AccentId.custom:
        return Color(custom);
    }
  }

  /// Swatch shown in pickers (dark-theme variant).
  static Color swatch(AccentId id, int custom) => color(id, Brightness.dark, custom);
}

class AppTheme {
  static Color _shift(Color c, double dh, double dl) {
    final h = HSLColor.fromColor(c);
    return h
        .withHue((h.hue + dh) % 360)
        .withLightness((h.lightness + dl).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  static ThemeData build(Brightness b, AccentId id, int custom, bool blur) {
    final dark = b == Brightness.dark;
    final accent = Accents.color(id, b, custom);
    final pal = XPalette(
      // Greyish-blue + black base
      bg: dark
          ? const [Color(0xFF090C11), Color(0xFF0F1620), Color(0xFF16202D)]
          : const [Color(0xFFEBF0F6), Color(0xFFDDE6EF), Color(0xFFCCD8E5)],
      glass: Colors.white,
      border: dark ? const Color(0x24FFFFFF) : const Color(0x99FFFFFF),
      accent: accent,
      accent2: _shift(accent, 28, 0.04),
      text: dark ? const Color(0xFFE8EEF5) : const Color(0xFF0F1722),
      dim: dark ? const Color(0xFF8B98A9) : const Color(0xFF5B6878),
      ok: dark ? const Color(0xFF4DB47E) : const Color(0xFF2F9660),
      danger: dark ? const Color(0xFFE06C75) : const Color(0xFFC0392B),
      blur: blur,
      dark: dark,
    );
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b)
        .copyWith(primary: accent, onSurface: pal.text, surface: pal.bg[1]);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: pal.bg[1],
      dividerColor: pal.border,
      extensions: [pal],
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? pal.onAccent : pal.dim),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? pal.accent : pal.border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
