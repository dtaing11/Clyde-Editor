import 'package:flutter/services.dart';

import '../../../core/commands/property_commands.dart';
import '../../../core/tools/editor_tool.dart';
import '../../../riv/riv_format.dart';

/// Eyedropper tool (I): samples the fill colour of the shape clicked
/// and applies it to every selected shape's fill.
///
/// One click is one undo entry (all selected fills change through a
/// single [SetComponentColorCommand]). When nothing is selected, the
/// click only samples: the selection is replaced by the sampled shape
/// so the inspector shows the picked colour.
final class EyedropperTool extends EditorTool {
  EyedropperTool();

  static const String toolId = 'eyedropper';

  @override
  String get id => toolId;

  @override
  String get label => 'Eyedropper';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyI;

  @override
  MouseCursor get cursor => SystemMouseCursors.precise;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    final hit = context.hitTester.hitTest(event.scenePosition);
    if (hit == null) return;

    final sampled = context.fillPaintOf(hit.ref);
    if (sampled == null) return;

    // Targets: every selected component's fill except the sampled one.
    final targets = <int>[];
    for (final ref in context.selection.selected) {
      if (ref == hit.ref) continue;
      final fill = context.fillPaintOf(ref);
      if (fill != null) targets.add(fill.solidColorComponentIndex);
    }

    if (targets.isEmpty) {
      // Pure sample: select the source so the inspector shows it.
      context.selection.select([hit.ref]);
      return;
    }

    context.dispatch(
      SetComponentColorCommand(
        artboardOrdinal: context.activeArtboardOrdinal,
        componentIndexes: targets,
        propertyKey: RivPropertyKeys.solidColorValue,
        color: sampled.color,
      ),
    );
  }
}
