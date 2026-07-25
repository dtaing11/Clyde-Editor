import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/selection_service.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_hierarchy.dart';
import '../../../shared/widgets/editor_context_menu.dart';
import '../state/editor_state.dart';
import '../state/scene_hierarchy_controller.dart';
import '../state/scene_tree_flattener.dart';
import 'editor_panel.dart';

/// Scene hierarchy: searchable component tree per artboard with rename,
/// drag-and-drop reparenting, lock, hide, duplicate, and delete.
///
/// Rendering is virtualised (§2.2): trees flatten to visible rows once
/// per state change and `ListView.builder` instantiates only on-screen
/// rows, keeping scrolling flat-cost regardless of node count.
class SceneHierarchyPanel extends StatelessWidget {
  const SceneHierarchyPanel({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return EditorPanel(
      title: 'Scene',
      child: ListenableBuilder(
        listenable: Listenable.merge([state.scene, state.selection]),
        builder: (context, _) {
          final rows = SceneTreeFlattener.flatten(
            state.hierarchyTrees,
            state.scene,
          );
          return Column(
            children: [
              _SearchField(controller: state.scene),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? const _EmptyScene()
                    : ListView.builder(
                        itemCount: rows.length,
                        itemExtent: 26,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _NodeRow(
                            key: ValueKey(row.ref),
                            state: state,
                            rows: rows,
                            node: row.node,
                            nodeRef: row.ref,
                            ancestorIndices: row.ancestorIndices,
                            depth: row.depth,
                            expanded:
                                state.scene.isSearching ||
                                state.scene.isExpanded(row.ref),
                            hasChildren: row.hasChildren,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyScene extends StatelessWidget {
  const _EmptyScene();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No document',
        style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final SceneHierarchyController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextField(
        onChanged: controller.setSearchQuery,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          hintText: 'Search components…',
          hintStyle: TextStyle(fontSize: 12, color: EditorTheme.textSecondary),
          prefixIcon: Icon(Icons.search, size: 14),
          prefixIconConstraints: BoxConstraints(minWidth: 30),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 7),
        ),
      ),
    );
  }
}

/// Payload carried during a hierarchy drag.
class _DragPayload {
  const _DragPayload(this.ref, this.label);

  final SceneNodeRef ref;
  final String label;
}

class _NodeRow extends StatefulWidget {
  const _NodeRow({
    super.key,
    required this.state,
    required this.rows,
    required this.node,
    required this.nodeRef,
    required this.ancestorIndices,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
  });

  final EditorState state;

  /// Currently visible rows, for shift-range selection ordering.
  final List<SceneTreeRow> rows;

  final RivHierarchyNode node;
  final SceneNodeRef nodeRef;
  final List<int> ancestorIndices;
  final int depth;
  final bool expanded;
  final bool hasChildren;

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  bool _dropHighlight = false;

  SceneHierarchyController get _scene => widget.state.scene;
  bool get _isArtboardRoot => widget.nodeRef.componentIndex == 0;
  bool get _locked =>
      _scene.isEffectivelyLocked(widget.nodeRef, widget.ancestorIndices);

  bool _canAcceptDrop(_DragPayload payload) {
    if (payload.ref.artboardOrdinal != widget.nodeRef.artboardOrdinal) {
      return false;
    }
    if (payload.ref == widget.nodeRef) return false;
    if (widget.ancestorIndices.contains(payload.ref.componentIndex)) {
      return false; // Cannot drop a node into its own subtree.
    }
    return !_locked;
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: widget.node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: SizedBox(
          width: 260,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      await widget.state.renameComponent(widget.nodeRef, newName.trim());
    }
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    final hidden = widget.state.isComponentHidden(widget.nodeRef);
    final locked = _scene.isLocked(widget.nodeRef);
    final action = await showEditorContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        const ContextMenuEntry(
          value: 'rename',
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
        ),
        const ContextMenuEntry(
          value: 'duplicate',
          label: 'Duplicate',
          icon: Icons.copy_outlined,
        ),
        ContextMenuEntry(
          value: 'lock',
          label: locked ? 'Unlock' : 'Lock',
          icon: locked ? Icons.lock_open : Icons.lock_outline,
        ),
        ContextMenuEntry(
          value: 'hide',
          label: hidden ? 'Show' : 'Hide',
          icon: hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
        const ContextMenuEntry(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          dividerBefore: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _showRenameDialog();
      case 'duplicate':
        await widget.state.duplicateComponent(widget.nodeRef);
      case 'lock':
        _scene.toggleLocked(widget.nodeRef);
      case 'hide':
        await widget.state.setComponentHidden(widget.nodeRef, !hidden);
      case 'delete':
        await widget.state.deleteComponent(widget.nodeRef);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selection.contains(widget.nodeRef);
    final hidden = widget.state.isComponentHidden(widget.nodeRef);

    final row = _RowContent(
      node: widget.node,
      depth: widget.depth,
      expanded: widget.expanded,
      hasChildren: widget.hasChildren,
      selected: selected,
      locked: _locked,
      hidden: hidden,
      dropHighlight: _dropHighlight,
      onToggleExpand: () => _scene.toggleExpanded(widget.nodeRef),
      onToggleLock: () => _scene.toggleLocked(widget.nodeRef),
      onToggleHide: () =>
          widget.state.setComponentHidden(widget.nodeRef, !hidden),
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final hardware = HardwareKeyboard.instance;
        final selection = widget.state.selection;
        final anchor = selection.anchor;
        if (hardware.isShiftPressed && anchor != null) {
          selection.select(
            SceneTreeFlattener.rangeBetween(
              widget.rows,
              anchor,
              widget.nodeRef,
            ),
            mode: SelectionMode.range,
          );
          return;
        }
        final toggle = hardware.isMetaPressed || hardware.isControlPressed;
        selection.select([
          widget.nodeRef,
        ], mode: toggle ? SelectionMode.toggle : SelectionMode.replace);
      },
      onDoubleTap: _isArtboardRoot || _locked ? null : _showRenameDialog,
      onSecondaryTapUp: _isArtboardRoot
          ? null
          : (details) => _showContextMenu(details.globalPosition),
      child: row,
    );

    final target = DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (details) {
        final accept = _canAcceptDrop(details.data);
        if (accept) setState(() => _dropHighlight = true);
        return accept;
      },
      onLeave: (_) => setState(() => _dropHighlight = false),
      onAcceptWithDetails: (details) {
        setState(() => _dropHighlight = false);
        widget.state.reparentComponent(
          details.data.ref,
          widget.nodeRef.componentIndex,
        );
      },
      builder: (context, _, _) => interactive,
    );

    if (_isArtboardRoot || _locked) return target;

    return Draggable<_DragPayload>(
      data: _DragPayload(widget.nodeRef, widget.node.label),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: EditorTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: EditorTheme.accent),
          ),
          child: Text(
            widget.node.label,
            style: const TextStyle(
              fontSize: 12,
              color: EditorTheme.textPrimary,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: target),
      child: target,
    );
  }
}

/// Pure visual row: indent, disclosure, icon, label, lock/hide toggles.
class _RowContent extends StatelessWidget {
  const _RowContent({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
    required this.selected,
    required this.locked,
    required this.hidden,
    required this.dropHighlight,
    required this.onToggleExpand,
    required this.onToggleLock,
    required this.onToggleHide,
  });

  final RivHierarchyNode node;
  final int depth;
  final bool expanded;
  final bool hasChildren;
  final bool selected;
  final bool locked;
  final bool hidden;
  final bool dropHighlight;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleLock;
  final VoidCallback onToggleHide;

  static const Map<int, IconData> _typeIcons = {
    1: Icons.crop_square,
    2: Icons.circle_outlined,
    3: Icons.pentagon_outlined,
    4: Icons.circle_outlined,
    7: Icons.rectangle_outlined,
    16: Icons.timeline,
    20: Icons.format_color_fill,
    24: Icons.border_color,
    40: Icons.linear_scale,
    41: Icons.linear_scale,
    134: Icons.text_fields,
  };

  @override
  Widget build(BuildContext context) {
    Color? background;
    if (dropHighlight) {
      background = EditorTheme.accent.withValues(alpha: 0.3);
    } else if (selected) {
      background = EditorTheme.accent.withValues(alpha: 0.16);
    }

    final labelColor = hidden
        ? EditorTheme.textSecondary.withValues(alpha: 0.5)
        : selected
        ? EditorTheme.textPrimary
        : EditorTheme.textSecondary;

    return Container(
      height: 26,
      color: background,
      padding: EdgeInsets.only(left: 6.0 + depth * 14),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: hasChildren
                ? InkWell(
                    onTap: onToggleExpand,
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 15,
                      color: EditorTheme.textSecondary,
                    ),
                  )
                : null,
          ),
          Icon(
            _typeIcons[node.typeKey] ?? Icons.widgets_outlined,
            size: 13,
            color: selected ? EditorTheme.accent : EditorTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              node.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          ),
          if (locked || hidden) ...[
            _RowToggle(
              icon: locked ? Icons.lock : Icons.lock_open,
              active: locked,
              onTap: onToggleLock,
            ),
            _RowToggle(
              icon: hidden ? Icons.visibility_off : Icons.visibility,
              active: hidden,
              onTap: onToggleHide,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _RowToggle extends StatelessWidget {
  const _RowToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(
          icon,
          size: 13,
          color: active ? EditorTheme.accent : EditorTheme.textSecondary,
        ),
      ),
    );
  }
}
