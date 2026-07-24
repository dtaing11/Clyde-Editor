import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../services/file_service.dart';
import '../state/editor_state.dart';

/// Top application toolbar: file lifecycle actions, edit history, and
/// document status.
///
/// All disk access goes through [FileService]; this widget only
/// orchestrates dialogs and reports outcomes.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.state, required this.files});

  final EditorState state;
  final FileService files;

  Future<void> _newDocument(BuildContext context) async {
    final ok = await state.newDocument();
    if (!ok && context.mounted) {
      _showMessage(context, 'Could not create document');
    }
  }

  Future<void> _openFile(BuildContext context) async {
    final picked = await files.openRiveFile();
    if (picked.result != FileOpResult.success) {
      if (picked.result == FileOpResult.failed && context.mounted) {
        _showMessage(context, 'Could not read file');
      }
      return;
    }
    final ok = await state.loadFromBytes(picked.name!, picked.bytes!);
    if (ok) {
      state.setFilePath(picked.path);
    } else if (context.mounted) {
      _showMessage(context, 'Could not open Rive file');
    }
  }

  Future<void> _save(BuildContext context) async {
    final path = state.filePath;
    if (path == null) return _saveAs(context);

    final bytes = state.exportBytes();
    if (bytes == null) return;
    final result = await files.writeTo(path, bytes);
    if (result == FileOpResult.success) {
      state.markSaved();
      if (context.mounted) _showMessage(context, 'Saved');
    } else if (context.mounted) {
      _showMessage(context, 'Save failed');
    }
  }

  Future<void> _saveAs(BuildContext context) async {
    final bytes = state.exportBytes();
    final doc = state.document;
    if (bytes == null || doc == null) return;

    final saved = await files.saveAs(bytes, suggestedName: '${doc.name}.riv');
    if (saved.result == FileOpResult.success) {
      state
        ..setFilePath(saved.path)
        ..markSaved();
      if (context.mounted) _showMessage(context, 'Saved');
    } else if (saved.result == FileOpResult.failed && context.mounted) {
      _showMessage(context, 'Save failed');
    }
  }

  Future<void> _importImage(BuildContext context) async {
    final picked = await files.pickImageAsset();
    if (picked.result != FileOpResult.success) return;
    final ok = await state.importImageAsset(picked.name!, picked.bytes!);
    if (context.mounted) {
      _showMessage(context, ok ? 'Imported ${picked.name}' : 'Import failed');
    }
  }

  Future<void> _addArtboard(BuildContext context) async {
    final existing = state.document?.artboards.length ?? 0;
    await state.addArtboard('Artboard ${existing + 1}');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
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
          const SizedBox(width: 12),
          _FileMenu(
            enabledSave: state.canEdit,
            onNew: () => _newDocument(context),
            onOpen: () => _openFile(context),
            onSave: () => _save(context),
            onSaveAs: () => _saveAs(context),
            onImportImage: () => _importImage(context),
            onAddArtboard: state.canEdit ? () => _addArtboard(context) : null,
          ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.undo,
            tooltip: 'Undo (Cmd/Ctrl+Z)',
            onPressed: state.canUndo ? state.undo : null,
          ),
          _IconAction(
            icon: Icons.redo,
            tooltip: 'Redo (Cmd/Ctrl+Shift+Z)',
            onPressed: state.canRedo ? state.redo : null,
          ),
          const Spacer(),
          _DocumentStatus(state: state),
        ],
      ),
    );
  }
}

/// "File" dropdown grouping the document lifecycle actions.
class _FileMenu extends StatelessWidget {
  const _FileMenu({
    required this.enabledSave,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onImportImage,
    required this.onAddArtboard,
  });

  final bool enabledSave;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onImportImage;
  final VoidCallback? onAddArtboard;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.description_outlined, size: 16),
        label: const Text('File', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: EditorTheme.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      menuChildren: [
        _menuItem('New', 'Cmd/Ctrl+N', onNew),
        _menuItem('Open…', 'Cmd/Ctrl+O', onOpen),
        const Divider(height: 1),
        _menuItem('Save', 'Cmd/Ctrl+S', enabledSave ? onSave : null),
        _menuItem(
          'Save As…',
          'Shift+Cmd/Ctrl+S',
          enabledSave ? onSaveAs : null,
        ),
        const Divider(height: 1),
        _menuItem('Import Image…', null, enabledSave ? onImportImage : null),
        _menuItem('Add Artboard', null, onAddArtboard),
      ],
    );
  }

  MenuItemButton _menuItem(
    String label,
    String? shortcut,
    VoidCallback? onPressed,
  ) {
    return MenuItemButton(
      onPressed: onPressed,
      trailingIcon: shortcut == null
          ? null
          : Text(
              shortcut,
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.textSecondary,
              ),
            ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// Right-aligned file name, dirty dot, and autosave time.
class _DocumentStatus extends StatelessWidget {
  const _DocumentStatus({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final doc = state.document;
    if (doc == null) return const SizedBox.shrink();

    final autosave = state.lastAutosaveTime;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (autosave != null) ...[
          Text(
            'autosaved '
            '${autosave.hour.toString().padLeft(2, '0')}:'
            '${autosave.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 10,
              color: EditorTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          '${doc.name}.riv${state.hasUnsavedChanges ? ' •' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: state.hasUnsavedChanges
                ? EditorTheme.accent
                : EditorTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
