import 'dart:io';

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
      _showMessage(context, 'Could not open Rive file');
    }
  }

  Future<void> _saveFile(BuildContext context) async {
    final bytes = state.exportBytes();
    final doc = state.document;
    if (bytes == null || doc == null) return;

    final location = await getSaveLocation(
      suggestedName: '${doc.name}.riv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Rive files', extensions: ['riv']),
      ],
    );
    if (location == null) return;

    try {
      await File(location.path).writeAsBytes(bytes, flush: true);
      state.markSaved();
      if (context.mounted) {
        _showMessage(context, 'Saved ${location.path.split('/').last}');
      }
    } on FileSystemException catch (e) {
      if (context.mounted) _showMessage(context, 'Save failed: ${e.message}');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'assets/branding/clyde_logo.png',
              width: 22,
              height: 22,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Clyde Editor',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 16),
          _ToolbarButton(
            icon: Icons.folder_open,
            label: 'Open',
            onPressed: () => _openFile(context),
          ),
          _ToolbarButton(
            icon: Icons.save_outlined,
            label: 'Save',
            onPressed: state.canEdit ? () => _saveFile(context) : null,
          ),
          const Spacer(),
          if (state.document != null)
            Text(
              '${state.document!.name}.riv'
              '${state.hasUnsavedChanges ? ' •' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: state.hasUnsavedChanges
                    ? EditorTheme.accent
                    : EditorTheme.textSecondary,
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
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: EditorTheme.textPrimary,
        disabledForegroundColor: EditorTheme.textSecondary.withValues(
          alpha: 0.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}
