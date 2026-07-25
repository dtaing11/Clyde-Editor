import 'package:flutter/material.dart';

import '../../core/theme/editor_theme.dart';

/// One entry of an editor context menu.
final class ContextMenuEntry<T> {
  const ContextMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Destructive actions render in the warning colour.
  final bool destructive;

  /// Draws a separator above this entry.
  final bool dividerBefore;
}

/// Shows a compact, editor-styled context menu at [globalPosition].
///
/// Wraps [showMenu] with the row height and typography used across the
/// editor, so panels never restyle menus individually (§5.4: shared
/// widgets are feature-agnostic).
Future<T?> showEditorContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<ContextMenuEntry<T>> entries,
}) {
  const double rowHeight = 28;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: [
      for (final entry in entries) ...[
        if (entry.dividerBefore) const PopupMenuDivider(height: 5),
        PopupMenuItem<T>(
          value: entry.value,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (entry.icon != null) ...[
                Icon(
                  entry.icon,
                  size: 14,
                  color: entry.destructive
                      ? EditorTheme.playhead
                      : EditorTheme.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                entry.label,
                style: TextStyle(
                  fontSize: 12,
                  color: entry.destructive
                      ? EditorTheme.playhead
                      : EditorTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
