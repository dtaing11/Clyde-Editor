import 'package:flutter/material.dart';

import '../../../core/model/property_metadata.dart';
import '../../../core/model/scene_node_ref.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_document_model.dart';
import '../../../riv/riv_keyframe_evaluator.dart';
import '../state/editor_state.dart';
import 'editor_panel.dart';
import 'property_grid.dart';

/// Right-side inspector.
///
/// Top: metadata-generated property grid for the primary selection
/// (§2.5, editable via commands). Below: animated property values at
/// the playhead when the selection is keyed in the current animation.
class InspectorPanel extends StatelessWidget {
  InspectorPanel({super.key, required this.state});

  final EditorState state;

  /// Property metadata registry; construction is cheap and pure, and
  /// panel instances are rebuilt only on editor-level changes.
  final PropertyMetadataRegistry registry = PropertyMetadataRegistry.standard();

  @override
  Widget build(BuildContext context) {
    return EditorPanel(
      title: 'Inspector',
      child: ListenableBuilder(
        listenable: Listenable.merge([state.selection, state]),
        builder: (context, _) {
          final primary = state.selection.primary;
          if (primary == null) return const _EmptyInspector();

          final keyedObject = state.selectedKeyedObject;
          final animationModel = state.selectedAnimationModel;
          return ListView(
            padding: const EdgeInsets.all(10),
            children: [
              _SelectionHeader(
                state: state,
                nodeRef: primary,
                selectionCount: state.selection.count,
              ),
              PropertyGrid(state: state, registry: registry, nodeRef: primary),
              if (keyedObject != null && animationModel != null)
                _AnimatedValuesSection(
                  keyedObject: keyedObject,
                  animation: animationModel,
                  currentTime: state.currentTime,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Name row for the current selection.
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.state,
    required this.nodeRef,
    required this.selectionCount,
  });

  final EditorState state;
  final SceneNodeRef nodeRef;
  final int selectionCount;

  String get _label {
    final trees = state.hierarchyTrees;
    if (nodeRef.artboardOrdinal < trees.length) {
      final node = _find(trees[nodeRef.artboardOrdinal]);
      if (node != null) return node.label;
    }
    return 'Component ${nodeRef.componentIndex}';
  }

  dynamic _find(dynamic node) {
    if (node.componentIndex == nodeRef.componentIndex) return node;
    for (final child in node.children) {
      final found = _find(child);
      if (found != null) return found;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.widgets_outlined, size: 14, color: EditorTheme.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            selectionCount > 1
                ? '$_label  (+${selectionCount - 1} more)'
                : _label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: EditorTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyInspector extends StatelessWidget {
  const _EmptyInspector();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Select an object in the scene or timeline\nto inspect it',
          textAlign: TextAlign.center,
          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}

/// Animated property values at the playhead for a keyed selection.
class _AnimatedValuesSection extends StatelessWidget {
  const _AnimatedValuesSection({
    required this.keyedObject,
    required this.animation,
    required this.currentTime,
  });

  final RivKeyedObjectModel keyedObject;
  final RivAnimationModel animation;
  final double currentTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const _SectionHeader(icon: Icons.tune, title: 'Animated properties'),
        const SizedBox(height: 4),
        _InfoRow(label: 'Tracks', value: '${keyedObject.properties.length}'),
        _InfoRow(
          label: 'Playhead',
          value: '${currentTime.toStringAsFixed(3)}s',
        ),
        const SizedBox(height: 4),
        for (final property in keyedObject.properties)
          _PropertyValueTile(
            property: property,
            animation: animation,
            currentTime: currentTime,
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: EditorTheme.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: EditorTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: EditorTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One animated property with its live value at the playhead.
class _PropertyValueTile extends StatelessWidget {
  const _PropertyValueTile({
    required this.property,
    required this.animation,
    required this.currentTime,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;
  final double currentTime;

  @override
  Widget build(BuildContext context) {
    final value = RivKeyframeEvaluator.evaluate(
      property,
      currentTime,
      animation.fps,
    );
    final approximate =
        value != null && RivKeyframeEvaluator.isApproximate(property);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              property.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
          if (value != null) ...[
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: EditorTheme.accent,
              ),
            ),
            if (approximate)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: 'Approximate (cubic curve shown linearly)',
                  child: Text(
                    '~',
                    style: TextStyle(
                      fontSize: 11,
                      color: EditorTheme.textSecondary,
                    ),
                  ),
                ),
              ),
          ] else
            Text(
              '${property.keyframes.length} keys',
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
