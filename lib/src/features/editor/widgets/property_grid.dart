import 'package:flutter/material.dart';

import '../../../core/commands/property_commands.dart';
import '../../../core/model/property_metadata.dart';
import '../../../core/model/scene_node_ref.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_format.dart';
import '../../../riv/riv_hierarchy.dart';
import '../../../riv/riv_raw_document.dart';
import '../../../riv/riv_shape_paints.dart';
import '../../../shared/widgets/color_picker.dart';
import '../state/editor_state.dart';

/// Property grid generated from [PropertyMetadataRegistry] (§2.5:
/// no per-node-type widget code).
///
/// Shows the primary selected component's editable properties grouped
/// by section. Values are read from the raw document; edits dispatch
/// mergeable [SetComponentPropertyCommand]s, so dragging a field is a
/// single undo entry.
class PropertyGrid extends StatelessWidget {
  const PropertyGrid({
    super.key,
    required this.state,
    required this.registry,
    required this.nodeRef,
  });

  final EditorState state;
  final PropertyMetadataRegistry registry;
  final SceneNodeRef nodeRef;

  @override
  Widget build(BuildContext context) {
    final object = _componentObject();
    if (object == null) return const SizedBox.shrink();

    final descriptors = registry.forType(object.typeKey);
    final paintFields = _paintFields();
    if (descriptors.isEmpty && paintFields.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: Text(
          'No editable properties',
          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
        ),
      );
    }

    final groups = <String, List<PropertyDescriptor>>{};
    for (final descriptor in descriptors) {
      groups.putIfAbsent(descriptor.group, () => []).add(descriptor);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              entry.key.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
          for (final descriptor in entry.value)
            NumericPropertyField(
              key: ValueKey('${nodeRef.componentIndex}:${descriptor.key}'),
              descriptor: descriptor,
              value: _valueOf(object, descriptor),
              onChanged: (value) => state.dispatch(
                SetComponentPropertyCommand(
                  artboardOrdinal: nodeRef.artboardOrdinal,
                  componentIndex: nodeRef.componentIndex,
                  propertyKey: descriptor.key,
                  value: value,
                ),
              ),
              onKeyframe: state.selectedAnimationModel == null
                  ? null
                  : () => state.insertKeyframe(
                      objectId: nodeRef.componentIndex,
                      propertyKey: descriptor.key,
                      value: _valueOf(object, descriptor),
                    ),
            ),
        ],
        if (paintFields.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              'PAINT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
          ...paintFields,
        ],
      ],
    );
  }

  /// Fill/stroke colour editors for the selected component, resolved
  /// through [RivShapePaints]; empty when it has no solid paints.
  List<Widget> _paintFields() {
    final raw = state.document?.editor?.raw;
    if (raw == null) return const [];

    Widget? fieldFor(String label, RivPaintTarget? target) {
      if (target == null) return null;
      return ColorField(
        key: ValueKey('${nodeRef.componentIndex}:$label:${target.color}'),
        label: label,
        color: target.color,
        onChanged: (color) => state.dispatch(
          SetComponentColorCommand(
            artboardOrdinal: nodeRef.artboardOrdinal,
            componentIndexes: [target.solidColorComponentIndex],
            propertyKey: RivPropertyKeys.solidColorValue,
            color: color,
          ),
        ),
      );
    }

    return [
      ?fieldFor(
        'Fill',
        RivShapePaints.fillOf(
          raw,
          nodeRef.artboardOrdinal,
          nodeRef.componentIndex,
        ),
      ),
      ?fieldFor(
        'Stroke',
        RivShapePaints.strokeOf(
          raw,
          nodeRef.artboardOrdinal,
          nodeRef.componentIndex,
        ),
      ),
    ];
  }

  RivRawObject? _componentObject() {
    final raw = state.document?.editor?.raw;
    if (raw == null) return null;
    return RivHierarchy.componentObjectAt(
      raw,
      nodeRef.artboardOrdinal,
      nodeRef.componentIndex,
    );
  }

  static double _valueOf(RivRawObject object, PropertyDescriptor descriptor) {
    final property = object.property(descriptor.key);
    if (property == null || property.fieldType != RivFieldType.float) {
      return descriptor.defaultValue;
    }
    return property.floatValue;
  }
}

/// Numeric field with drag-to-adjust, text entry, and an optional
/// keyframe button.
class NumericPropertyField extends StatefulWidget {
  const NumericPropertyField({
    super.key,
    required this.descriptor,
    required this.value,
    required this.onChanged,
    this.onKeyframe,
  });

  final PropertyDescriptor descriptor;
  final double value;
  final ValueChanged<double> onChanged;

  /// Keys the current value at the playhead; `null` hides the button
  /// (no animation selected).
  final VoidCallback? onKeyframe;

  @override
  State<NumericPropertyField> createState() => _NumericPropertyFieldState();
}

class _NumericPropertyFieldState extends State<NumericPropertyField> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  bool _editing = false;

  static String _format(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void didUpdateWidget(NumericPropertyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _clamp(double value) {
    final min = widget.descriptor.min;
    final max = widget.descriptor.max;
    var result = value;
    if (min != null && result < min) result = min;
    if (max != null && result > max) result = max;
    return result;
  }

  void _commitText() {
    final parsed = double.tryParse(_controller.text);
    if (parsed != null) {
      widget.onChanged(_clamp(parsed));
    } else {
      _controller.text = _format(widget.value);
    }
    setState(() => _editing = false);
  }

  void _dragBy(double deltaPixels) {
    final next = _clamp(
      widget.value + deltaPixels * widget.descriptor.dragStep,
    );
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => _dragBy(details.delta.dx),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Text(
                  widget.descriptor.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: EditorTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          if (widget.onKeyframe != null) ...[
            Tooltip(
              message: 'Keyframe at playhead',
              child: InkWell(
                onTap: widget.onKeyframe,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.change_history,
                    size: 11,
                    color: EditorTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          SizedBox(
            width: 72,
            height: 22,
            child: TextField(
              controller: _controller,
              onTap: () => setState(() => _editing = true),
              onSubmitted: (_) => _commitText(),
              onTapOutside: (_) {
                if (_editing) _commitText();
              },
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: EditorTheme.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                filled: true,
                fillColor: EditorTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
