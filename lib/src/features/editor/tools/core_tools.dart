import 'dart:ui';

import 'package:flutter/services.dart';

import '../../../core/commands/property_commands.dart';
import '../../../core/model/scene_node_ref.dart';
import '../../../core/services/selection_service.dart';
import '../../../core/tools/editor_tool.dart';

/// Selection tool: the default pointer (§2.2/§2.3).
///
/// Click selects the topmost component under the cursor (cmd/ctrl-click
/// toggles); dragging a selected component moves the whole selection
/// (one undo entry per drag); dragging from empty space draws a marquee
/// that selects every intersecting component on release.
final class SelectionTool extends EditorTool {
  SelectionTool();

  static const String toolId = 'selection';

  /// Pointer travel below this (in view px) counts as a click, not a
  /// move, so selecting never accidentally nudges a shape.
  static const double _dragThreshold = 3;

  Offset? _marqueeStartView;
  Offset? _marqueeEndView;
  Offset? _marqueeStartScene;
  Offset? _marqueeEndScene;

  /// Drag-to-move state: scene-space grab point and the starting local
  /// translation of every dragged component.
  Offset? _dragStartScene;
  Offset? _dragStartView;
  bool _dragActive = false;
  final Map<SceneNodeRef, Offset> _dragOrigins = {};

  /// Current marquee rectangle in view coordinates, or `null`.
  Rect? get marqueeRect {
    final start = _marqueeStartView;
    final end = _marqueeEndView;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  @override
  String get id => toolId;

  @override
  String get label => 'Select';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyV;

  @override
  MouseCursor get cursor => SystemMouseCursors.basic;

  static SelectionMode _modeOf(ToolPointerEvent event) =>
      event.isToggleModifierPressed
      ? SelectionMode.toggle
      : SelectionMode.replace;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    final hit = context.hitTester.hitTest(event.scenePosition);
    if (hit != null) {
      // Toggle-clicks only adjust selection; plain clicks select (when
      // needed) and arm a move of everything selected.
      if (event.isToggleModifierPressed) {
        context.selection.select([hit.ref], mode: SelectionMode.toggle);
        return;
      }
      if (!context.selection.contains(hit.ref)) {
        context.selection.select([hit.ref], mode: SelectionMode.replace);
      }
      _armDrag(context, event);
      return;
    }
    // Empty space: begin a marquee.
    _marqueeStartView = event.viewPosition;
    _marqueeEndView = event.viewPosition;
    _marqueeStartScene = event.scenePosition;
    _marqueeEndScene = event.scenePosition;
    context.requestOverlayRepaint();
  }

  void _armDrag(ToolContext context, ToolPointerEvent event) {
    _dragStartScene = event.scenePosition;
    _dragStartView = event.viewPosition;
    _dragActive = false;
    _dragOrigins.clear();
    for (final ref in context.selection.selected) {
      final translation = context.componentTranslation(ref);
      if (translation != null) _dragOrigins[ref] = translation;
    }
  }

  @override
  void onPointerMove(ToolContext context, ToolPointerEvent event) {
    if (_dragStartScene != null) {
      _updateDrag(context, event);
      return;
    }
    if (_marqueeStartView == null) return;
    _marqueeEndView = event.viewPosition;
    _marqueeEndScene = event.scenePosition;
    context.requestOverlayRepaint();
  }

  void _updateDrag(ToolContext context, ToolPointerEvent event) {
    final startScene = _dragStartScene!;
    if (!_dragActive) {
      final travel = (event.viewPosition - _dragStartView!).distance;
      if (travel < _dragThreshold) return;
      _dragActive = true;
    }
    if (_dragOrigins.isEmpty) return;

    final delta = event.scenePosition - startScene;
    context.dispatch(
      MoveComponentsCommand(
        artboardOrdinal: context.activeArtboardOrdinal,
        moves: [
          for (final entry in _dragOrigins.entries)
            ComponentMove(
              componentIndex: entry.key.componentIndex,
              x: entry.value.dx + delta.dx,
              y: entry.value.dy + delta.dy,
            ),
        ],
      ),
    );
  }

  @override
  void onPointerUp(ToolContext context, ToolPointerEvent event) {
    if (_dragStartScene != null) {
      _dragStartScene = null;
      _dragStartView = null;
      _dragActive = false;
      _dragOrigins.clear();
      return;
    }

    final startScene = _marqueeStartScene;
    final endScene = _marqueeEndScene;
    _clearMarquee(context);
    if (startScene == null || endScene == null) return;

    final sceneRect = Rect.fromPoints(startScene, endScene);
    final hits = context.hitTester.hitTestRect(sceneRect);
    final refs = [for (final hit in hits) hit.ref];
    final mode = _modeOf(event);
    if (refs.isEmpty && mode == SelectionMode.replace) {
      context.selection.clear();
    } else if (refs.isNotEmpty) {
      context.selection.select(refs, mode: mode);
    }
  }

  void _clearMarquee(ToolContext context) {
    _marqueeStartView = null;
    _marqueeEndView = null;
    _marqueeStartScene = null;
    _marqueeEndScene = null;
    context.requestOverlayRepaint();
  }

  @override
  void deactivate(ToolContext context) {
    _marqueeStartView = null;
    _marqueeEndView = null;
    _marqueeStartScene = null;
    _marqueeEndScene = null;
    _dragStartScene = null;
    _dragStartView = null;
    _dragActive = false;
    _dragOrigins.clear();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext context) {
    _paintSelectionOutlines(canvas, context);

    final rect = marqueeRect;
    if (rect == null) return;
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x2257A5FF),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF57A5FF),
    );
  }

  void _paintSelectionOutlines(Canvas canvas, ToolContext context) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF57A5FF);
    final handle = Paint()..color = const Color(0xFF57A5FF);
    const handleRadius = 2.5;

    for (final SceneNodeRef ref in context.selection.selected) {
      final bounds = context.hitTester.boundsOf(ref);
      if (bounds == null) continue;
      final viewRect = Rect.fromPoints(
        context.viewTransform.sceneToView(bounds.topLeft),
        context.viewTransform.sceneToView(bounds.bottomRight),
      );
      canvas.drawRect(viewRect, outline);
      for (final corner in [
        viewRect.topLeft,
        viewRect.topRight,
        viewRect.bottomLeft,
        viewRect.bottomRight,
      ]) {
        canvas.drawCircle(corner, handleRadius, handle);
      }
    }
  }
}

/// Hand tool: pans the view by dragging.
final class HandTool extends EditorTool {
  HandTool();

  static const String toolId = 'hand';

  Offset? _lastViewPosition;

  @override
  String get id => toolId;

  @override
  String get label => 'Hand';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyH;

  @override
  MouseCursor get cursor => SystemMouseCursors.grab;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    _lastViewPosition = event.viewPosition;
  }

  @override
  void onPointerMove(ToolContext context, ToolPointerEvent event) {
    final last = _lastViewPosition;
    if (last == null) return;
    context.setViewTransform(
      context.viewTransform.pannedBy(event.viewPosition - last),
    );
    _lastViewPosition = event.viewPosition;
  }

  @override
  void onPointerUp(ToolContext context, ToolPointerEvent event) {
    _lastViewPosition = null;
  }

  @override
  void deactivate(ToolContext context) {
    _lastViewPosition = null;
  }
}

/// Zoom tool: click zooms in, secondary/alt click zooms out.
final class ZoomTool extends EditorTool {
  const ZoomTool();

  static const String toolId = 'zoom';
  static const double _stepFactor = 1.25;

  @override
  String get id => toolId;

  @override
  String get label => 'Zoom';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyZ;

  @override
  MouseCursor get cursor => SystemMouseCursors.zoomIn;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    final factor = event.isSecondary ? 1 / _stepFactor : _stepFactor;
    context.setViewTransform(
      context.viewTransform.zoomedBy(factor, viewAnchor: event.viewPosition),
    );
  }
}
