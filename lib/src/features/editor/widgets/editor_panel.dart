import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';

/// Reusable chrome for a docked editor panel: header bar + content.
class EditorPanel extends StatelessWidget {
  const EditorPanel({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EditorTheme.surface,
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: EditorTheme.panelHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: EditorTheme.surfaceAlt,
              border: Border(bottom: BorderSide(color: EditorTheme.border)),
            ),
            child: Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: EditorTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
