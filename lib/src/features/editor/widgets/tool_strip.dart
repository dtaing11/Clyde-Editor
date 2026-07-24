import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../core/tools/tool_controller.dart';

/// Vertical strip of tool buttons generated from the tool registry.
///
/// Adding a tool requires only a registration (§2.4); this widget never
/// changes.
class ToolStrip extends StatelessWidget {
  const ToolStrip({super.key, required this.controller});

  final ToolController controller;

  static const Map<String, IconData> _icons = {
    'selection': Icons.near_me_outlined,
    'hand': Icons.back_hand_outlined,
    'zoom': Icons.zoom_in,
    'rectangle': Icons.rectangle_outlined,
    'ellipse': Icons.circle_outlined,
    'polygon': Icons.pentagon_outlined,
    'text': Icons.text_fields,
    'pen': Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          width: 36,
          decoration: const BoxDecoration(
            color: EditorTheme.surfaceAlt,
            border: Border(right: BorderSide(color: EditorTheme.border)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 4),
              for (final tool in controller.registry.tools)
                _ToolButton(
                  icon: _icons[tool.id] ?? Icons.build_outlined,
                  label: tool.shortcut == null
                      ? tool.label
                      : '${tool.label} (${tool.shortcut!.keyLabel})',
                  selected: identical(tool, controller.activeTool),
                  onTap: () => controller.activate(tool.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? EditorTheme.accent.withValues(alpha: 0.22) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? EditorTheme.accent : EditorTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
