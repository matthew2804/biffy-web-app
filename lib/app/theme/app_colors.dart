import 'package:flutter/material.dart';

/// Paleta oficial de Biffy (amarillo abeja como primario).
abstract final class AppColors {
  static const primary = Color(0xFFFCBD1A);
  static const secondary = Color(0xFFF3B428);
  static const background = Color(0xFFF4F5F9);
  static const text = Color(0xFF1E1E20);
  static const success = Color(0xFF23A05B);
  static const error = Color(0xFFE85D57);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFEFEAFA);
  static const border = Color(0xFFE0E2E8);
  static const muted = Color(0xFF6B6E78);

  // Variantes para modo oscuro.
  static const darkBackground = Color(0xFF121214);
  static const darkSurface = Color(0xFF1E1E22);
  static const darkSurfaceSoft = Color(0xFF2A2638);
  static const darkBorder = Color(0xFF34353C);
  static const darkText = Color(0xFFF2F2F4);
  static const darkMuted = Color(0xFFA3A6B0);
}

/// Colores dependientes del tema (claro/oscuro) accesibles con `context.palette`.
@immutable
class BiffyPalette extends ThemeExtension<BiffyPalette> {
  const BiffyPalette({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.border,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color border;
  final Color text;
  final Color muted;

  static const light = BiffyPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceSoft: AppColors.surfaceSoft,
    border: AppColors.border,
    text: AppColors.text,
    muted: AppColors.muted,
  );

  static const dark = BiffyPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceSoft: AppColors.darkSurfaceSoft,
    border: AppColors.darkBorder,
    text: AppColors.darkText,
    muted: AppColors.darkMuted,
  );

  @override
  BiffyPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? border,
    Color? text,
    Color? muted,
  }) {
    return BiffyPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
    );
  }

  @override
  BiffyPalette lerp(BiffyPalette? other, double t) {
    if (other == null) return this;
    return BiffyPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  BiffyPalette get palette =>
      Theme.of(this).extension<BiffyPalette>() ?? BiffyPalette.light;
}
