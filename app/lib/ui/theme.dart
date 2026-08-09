import 'package:flutter/material.dart';

import '../domain/session_phase.dart';

/// Dark, high contrast, few colours.
///
/// The timer is read at a glance from across a room by someone out of breath,
/// so the palette does one job: tell you which phase you are in and whether you
/// are working or resting.
class AppTheme {
  const AppTheme._();

  static const Color background = Color(0xFF0E1013);
  static const Color surface = Color(0xFF181B20);
  static const Color surfaceAlt = Color(0xFF22262D);
  static const Color accent = Color(0xFFE8503A);
  static const Color work = Color(0xFFE8503A);
  static const Color rest = Color(0xFF2E9E7B);
  static const Color textPrimary = Color(0xFFF2F3F5);
  static const Color textSecondary = Color(0xFF9AA1AC);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: rest,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerColor: const Color(0xFF2A2F37),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: surfaceAlt,
      ),
    );
  }

  /// One colour per phase, used consistently across the breakdown bar, the
  /// configuration screen and the running timer.
  static Color phaseColor(SessionPhase phase) => switch (phase) {
    SessionPhase.warmUp => const Color(0xFFE0A030),
    SessionPhase.conditioning => const Color(0xFFE8503A),
    SessionPhase.shadow => const Color(0xFF3D7BD9),
    SessionPhase.technical => const Color(0xFF8A63D2),
    SessionPhase.coolDown => const Color(0xFF2E9E7B),
  };
}
