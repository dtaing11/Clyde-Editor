import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_hierarchy.dart';
import '../state/editor_state.dart';
import '../state/scene_hierarchy_controller.dart';
import 'editor_panel.dart';

/// Scene hierarchy: searchable component tree per artboard with rename,
/// drag-and-drop reparenting, lock, hide, duplicate, and delete.
class SceneHierarchyPanel extends StatelessWidget {
  const SceneHierarchyPanel({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return EditorPanel(
      title: 'Scene',
      child: ListenableBuilder(
        listenable: state.scene,
        builder: (context, _) {
          final trees = state.hierarchyTrees;
          return Column(
            children: [
              _SearchField(controller: state.scene),
              const Divider(height: 1),
              Expanded(
                child: trees.isEmpty
                    ? const _EmptyScene()
                    : ListView(
                        children: [
                          for (var i = 0; i < trees.length; i++)
                            _ArtboardSection(
                              state: state,
                              artboardOrdinal: i,
                              root: trees[i],
                            ),
                        ],
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

class _ArtboardSection extends StatelessWidget {
  const _ArtboardSection({
    required this.state,
    required this.artboardOrdinal,
    required this.root,
  });

  final EditorState state;
  final int artboardOrdinal;
  final RivHierarchyNode root;

  @override
  Widget build(BuildContext context) {
    final scene = state.scene;
    if (scene.isSearching && !scene.subtreeMatchesSearch(root)) {
      return const SizedBox.shrink();
    }
    return _HierarchyNodeTile(
      state: state,
      artboardOrdinal: artboardOrdinal,
      node: root,
      ancestorIndices: const [],
      depth: 0,
    );
  }
}

/// A single row plus (when expanded) its children.
class _HierarchyNodeTile extends StatelessWidget {
  const _HierarchyNodeTile({
    required this.state,
    required this.artboardOrdinal,
    required this.node,
    required this.ancestorIndices,
    required this.depth,
  });

  final EditorState state;
  final int artboardOrdinal;
  final RivHierarchyNode node;
  final List<int> ancestorIndices;
  final int depth;

  SceneNodeRef get _ref => SceneNodeRef(artboardOrdinal, node.componentIndex);

  @override
  Widget build(BuildContext context) {
    final scene = state.scene;

    // While searching, show any node whose subtree matches, expanded.
    if (scene.isSearching && !scene.subtreeMatchesSearch(node)) {
      return const SizedBox.shrink();
    }
    final expanded = scene.isSearching || scene.isExpanded(_ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NodeRow(
          state: state,
          node: node,
          nodeRef: _ref,
          ancestorIndices: ancestorIndices,
          depth: depth,
          expanded: expanded,
          hasChildren: node.children.isNotEmpty,
        ),
        if (expanded)
          for (final child in node.children)
            _HierarchyNodeTile(
              state: state,
              artboardOrdinal: artboardOrdinal,
              node: child,
              ancestorIndices: [...ancestorIndices, node.componentIndex],
              depth: depth + 1,
            ),
      ],
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
    required this.state,
    required this.node,
    required this.nodeRef,
    required this.ancestorIndices,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
  });

  final EditorState state;
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
        title: const Text('Rename', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          onSubmitted: (value) => Navigator.of(context).pop(value),
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
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'lock', child: Text(locked ? 'Unlock' : 'Lock')),
        PopupMenuItem(value: 'hide', child: Text(hidden ? 'Show' : 'Hide')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: EditorTheme.playhead)),
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
    final selected = _scene.selected == widget.nodeRef;
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
      onTap: () => _scene.select(widget.nodeRef),
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
