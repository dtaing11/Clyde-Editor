import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_document_model.dart';
import '../../../riv/riv_keyframe_evaluator.dart';
import '../state/editor_state.dart';
import 'editor_panel.dart';

/// Right-side inspector: shows the primary selected component and, when
/// it is animated in the current animation, its property values
/// evaluated at the playhead.
///
/// Selection comes from the shared `SelectionService` (§2.2); the
/// timeline's keyed-object clicks route through the same service.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return EditorPanel(
      title: 'Inspector',
      child: ListenableBuilder(
        listenable: state.selection,
        builder: (context, _) {
          final keyedObject = state.selectedKeyedObject;
          final animationModel = state.selectedAnimationModel;
          if (keyedObject == null || animationModel == null) {
            return const _EmptyInspector();
          }
          return _ObjectInspector(
            keyedObject: keyedObject,
            animation: animationModel,
            currentTime: state.currentTime,
            selectionCount: state.selection.count,
          );
        },
      ),
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

class _ObjectInspector extends StatelessWidget {
  const _ObjectInspector({
    required this.keyedObject,
    required this.animation,
    required this.currentTime,
    required this.selectionCount,
  });

  final RivKeyedObjectModel keyedObject;
  final RivAnimationModel animation;
  final double currentTime;
  final int selectionCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _SectionHeader(
          icon: Icons.widgets_outlined,
          title: selectionCount > 1
              ? '${keyedObject.objectName}  (+${selectionCount - 1} more)'
              : keyedObject.objectName,
        ),
        const SizedBox(height: 4),
        _InfoRow(label: 'Object index', value: '${keyedObject.objectId}'),
        _InfoRow(label: 'Tracks', value: '${keyedObject.properties.length}'),
        _InfoRow(
          label: 'Playhead',
          value: '${currentTime.toStringAsFixed(3)}s',
        ),
        const SizedBox(height: 12),
        const _SectionHeader(icon: Icons.tune, title: 'Animated properties'),
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
