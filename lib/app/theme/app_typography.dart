import 'package:flutter/material.dart';

/// Sora para títulos, Manrope para el resto (fuentes OFL incluidas en assets/fonts).
abstract final class AppTypography {
  static const heading = 'Sora';
  static const body = 'Manrope';

  /// Construye el tema de texto para un esquema de color dado.
  static TextTheme textTheme(Color text, Color muted) {
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: heading,
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      headlineSmall: TextStyle(
        fontFamily: heading,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleLarge: TextStyle(
        fontFamily: heading,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: TextStyle(
        fontFamily: body,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleSmall: TextStyle(
        fontFamily: body,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: TextStyle(fontFamily: body, fontSize: 16, color: text),
      bodyMedium: TextStyle(fontFamily: body, fontSize: 14, color: text),
      bodySmall: TextStyle(fontFamily: body, fontSize: 12, color: muted),
      labelLarge: TextStyle(
        fontFamily: body,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      labelMedium: TextStyle(
        fontFamily: body,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      labelSmall: TextStyle(
        fontFamily: body,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: muted,
      ),
    );
  }
}
