import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../state/editor_state.dart';

/// Top application toolbar: file actions and document info.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.state});

  final EditorState state;

  Future<void> _openFile(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'Rive files', extensions: ['riv']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name.replaceAll('.riv', '');
    final ok = await state.loadFromBytes(name, bytes);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open Rive file')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: EditorTheme.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: EditorTheme.surfaceAlt,
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.animation, color: EditorTheme.accent, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Rive Editor',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 16),
          _ToolbarButton(
            icon: Icons.folder_open,
            label: 'Open',
            onPressed: () => _openFile(context),
          ),
          const Spacer(),
          if (state.document != null)
            Text(
              '${state.document!.name}.riv',
              style: const TextStyle(
                fontSize: 12,
                color: EditorTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: EditorTheme.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}
