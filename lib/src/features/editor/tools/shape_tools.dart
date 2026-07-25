import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import '../../../core/commands/shape_commands.dart';
import '../../../core/tools/editor_tool.dart';
import '../../../riv/riv_shape_factory.dart';

/// Base for drag-to-size shape creation tools.
///
/// Drag defines the shape's bounds in scene space with a ghost preview
/// on the overlay; releasing dispatches an [AddShapeCommand]. Each
/// concrete tool supplies its [RivShapeKind] and overlay outline.
abstract base class ShapeCreationTool extends EditorTool {
  ShapeCreationTool();

  /// Minimum drag extent (scene units) below which release is a no-op,
  /// preventing accidental zero-size shapes from a click.
  static const double minimumExtent = 2;

  Offset? _dragStartScene;
  Offset? _dragCurrentScene;
  int _createdCount = 0;

  RivShapeKind get kind;

  /// Draws the ghost outline for [rect] (in view space).
  void paintGhost(Canvas canvas, Rect rect, Paint paint);

  /// Current drag rectangle in scene space, or `null`.
  Rect? get sceneRect {
    final start = _dragStartScene;
    final current = _dragCurrentScene;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  @override
  MouseCursor get cursor => SystemMouseCursors.precise;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    _dragStartScene = event.scenePosition;
    _dragCurrentScene = event.scenePosition;
    context.requestOverlayRepaint();
  }

  @override
  void onPointerMove(ToolContext context, ToolPointerEvent event) {
    if (_dragStartScene == null) return;
    _dragCurrentScene = event.scenePosition;
    context.requestOverlayRepaint();
  }

  @override
  void onPointerUp(ToolContext context, ToolPointerEvent event) {
    final rect = sceneRect;
    _dragStartScene = null;
    _dragCurrentScene = null;
    context.requestOverlayRepaint();

    if (rect == null ||
        context.activeArtboardOrdinal < 0 ||
        math.max(rect.width, rect.height) < minimumExtent) {
      return;
    }

    _createdCount++;
    context.dispatch(
      AddShapeCommand(
        artboardOrdinal: context.activeArtboardOrdinal,
        kind: kind,
        name: '$label $_createdCount',
        // The parametric path is centred on the shape's node.
        x: rect.center.dx,
        y: rect.center.dy,
        width: rect.width,
        height: rect.height,
      ),
    );
  }

  @override
  void deactivate(ToolContext context) {
    _dragStartScene = null;
    _dragCurrentScene = null;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext context) {
    final rect = sceneRect;
    if (rect == null) return;
    final viewRect = Rect.fromPoints(
      context.viewTransform.sceneToView(rect.topLeft),
      context.viewTransform.sceneToView(rect.bottomRight),
    );
    paintGhost(
      canvas,
      viewRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF57A5FF),
    );
  }
}

/// Drag-to-create rectangles.
final class RectangleTool extends ShapeCreationTool {
  RectangleTool();

  static const String toolId = 'rectangle';

  @override
  String get id => toolId;

  @override
  String get label => 'Rectangle';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyR;

  @override
  RivShapeKind get kind => RivShapeKind.rectangle;

  @override
  void paintGhost(Canvas canvas, Rect rect, Paint paint) {
    canvas.drawRect(rect, paint);
  }
}

/// Drag-to-create ellipses.
final class EllipseTool extends ShapeCreationTool {
  EllipseTool();

  static const String toolId = 'ellipse';

  @override
  String get id => toolId;

  @override
  String get label => 'Ellipse';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyO;

  @override
  RivShapeKind get kind => RivShapeKind.ellipse;

  @override
  void paintGhost(Canvas canvas, Rect rect, Paint paint) {
    canvas.drawOval(rect, paint);
  }
}
