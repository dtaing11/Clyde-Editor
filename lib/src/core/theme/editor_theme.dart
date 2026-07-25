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
      // Context menus (right-click) match the panel chrome instead of
      // the default elevated Material look.
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: border),
        ),
        textStyle: const TextStyle(fontSize: 12, color: textPrimary),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: textPrimary),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      // MenuAnchor-based menus (toolbar File menu).
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(surfaceAlt),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: border),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          foregroundColor: const WidgetStatePropertyAll(textPrimary),
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(160, 30)),
        ),
      ),
      // Dialogs (rename, confirmations).
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        contentTextStyle: const TextStyle(fontSize: 12, color: textPrimary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: accent),
        ),
        hintStyle: const TextStyle(fontSize: 12, color: textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: const TextStyle(fontSize: 12, color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
  }
}
