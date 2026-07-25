import 'package:flutter/material.dart';

import '../../../core/commands/property_commands.dart';
import '../../../core/model/property_metadata.dart';
import '../../../core/model/scene_node_ref.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_format.dart';
import '../../../riv/riv_raw_document.dart';
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
    if (descriptors.isEmpty) {
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
            ),
        ],
      ],
    );
  }

  RivRawObject? _componentObject() {
    final raw = state.document?.editor?.raw;
    if (raw == null) return null;
    final objects = _componentObjectsOf(raw, nodeRef.artboardOrdinal);
    return nodeRef.componentIndex < objects.length
        ? objects[nodeRef.componentIndex]
        : null;
  }

  static List<RivRawObject> _componentObjectsOf(
    RivRawDocument document,
    int artboardOrdinal,
  ) {
    const topLevelTypes = {
      RivTypeKeys.artboard,
      RivTypeKeys.backboard,
      RivTypeKeys.imageAsset,
      RivTypeKeys.fontAsset,
      RivTypeKeys.audioAsset,
      RivTypeKeys.fileAssetContents,
    };

    var seen = -1;
    for (var i = 0; i < document.objects.length; i++) {
      if (document.objects[i].typeKey != RivTypeKeys.artboard) continue;
      seen++;
      if (seen != artboardOrdinal) continue;

      final components = <RivRawObject>[document.objects[i]];
      for (var j = i + 1; j < document.objects.length; j++) {
        final object = document.objects[j];
        if (topLevelTypes.contains(object.typeKey)) break;
        final isComponent =
            !RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
            RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey);
        if (isComponent) components.add(object);
      }
      return components;
    }
    return const [];
  }

  static double _valueOf(RivRawObject object, PropertyDescriptor descriptor) {
    final property = object.property(descriptor.key);
    if (property == null || property.fieldType != RivFieldType.float) {
      return descriptor.defaultValue;
    }
    return property.floatValue;
  }
}

/// Numeric field with drag-to-adjust and text entry.
class NumericPropertyField extends StatefulWidget {
  const NumericPropertyField({
    super.key,
    required this.descriptor,
    required this.value,
    required this.onChanged,
  });

  final PropertyDescriptor descriptor;
  final double value;
  final ValueChanged<double> onChanged;

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
