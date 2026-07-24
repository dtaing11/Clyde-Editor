import 'package:flutter/material.dart';

/// Centralized design tokens and [ThemeData] for the editor.
///
/// Keep all colors, dimensions and text styles here so panels stay
/// visually consistent and re-themable.
abstract final class EditorTheme {
  // Palette
  static const Color background = Color(0xFF1D1D1D);
  static const Color surface = Color(0xFF252525);
  static const Color surfaceAlt = Color(0xFF2C2C2C);
  static const Color border = Color(0xFF3A3A3A);
  static const Color accent = Color(0xFF57A5FF);
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color viewportBackground = Color(0xFF161616);
  static const Color timelineTrack = Color(0xFF303030);
  static const Color playhead = Color(0xFFFF5A5A);

  // Dimensions
  static const double panelHeaderHeight = 32;
  static const double toolbarHeight = 40;
  static const double timelineHeight = 220;
  static const double sidePanelWidth = 260;

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );
    return base.copyWith(
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      iconTheme: const IconThemeData(color: textSecondary, size: 18),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}
