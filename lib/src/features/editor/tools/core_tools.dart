import 'dart:ui';

import 'package:flutter/services.dart';

import '../../../core/tools/editor_tool.dart';

/// Selection tool: the default pointer. Drags a marquee rectangle on
/// the overlay; selection semantics attach when the selection service
/// lands (tracked in PRODUCT_SPEC §2.2/§2.3 acceptance).
final class SelectionTool extends EditorTool {
  SelectionTool();

  static const String toolId = 'selection';

  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  /// Current marquee rectangle in view coordinates, or `null`.
  Rect? get marqueeRect {
    final start = _marqueeStart;
    final end = _marqueeEnd;
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

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    _marqueeStart = event.viewPosition;
    _marqueeEnd = event.viewPosition;
    context.requestOverlayRepaint();
  }

  @override
  void onPointerMove(ToolContext context, ToolPointerEvent event) {
    if (_marqueeStart == null) return;
    _marqueeEnd = event.viewPosition;
    context.requestOverlayRepaint();
  }

  @override
  void onPointerUp(ToolContext context, ToolPointerEvent event) {
    _marqueeStart = null;
    _marqueeEnd = null;
    context.requestOverlayRepaint();
  }

  @override
  void deactivate(ToolContext context) {
    _marqueeStart = null;
    _marqueeEnd = null;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext context) {
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
