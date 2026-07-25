import 'dart:ui';

import 'package:flutter/services.dart';

import '../commands/editor_command.dart';
import '../services/scene_hit_tester.dart';
import '../services/selection_service.dart';
import '../services/view_transform.dart';

/// Everything a tool may read or request during interaction.
///
/// Tools receive this instead of widgets or editor state, so the tool
/// layer stays free of panel knowledge (§2.4: adding a tool requires
/// zero changes to canvas or toolbar).
abstract interface class ToolContext {
  ViewTransform get viewTransform;

  /// Requests a view transform change (hand/zoom tools).
  void setViewTransform(ViewTransform transform);

  /// Requests an overlay repaint (marquee rectangles, previews).
  void requestOverlayRepaint();

  /// Ordinal of the artboard currently shown, or -1 when none.
  int get activeArtboardOrdinal;

  /// Dispatches a document mutation through the command system (§4.4).
  void dispatch(EditorCommand command);

  /// Hit tester over the active artboard's components (§2.3).
  SceneHitTester get hitTester;

  /// The shared selection (§2.2).
  SelectionService get selection;
}

/// A pointer event delivered to a tool, in both coordinate spaces.
final class ToolPointerEvent {
  const ToolPointerEvent({
    required this.viewPosition,
    required this.scenePosition,
    this.isSecondary = false,
  });

  final Offset viewPosition;
  final Offset scenePosition;
  final bool isSecondary;
}

/// Contract every canvas tool implements (§2.4).
///
/// Tools are stateless between activations; interaction state lives
/// inside the tool instance and is reset in [deactivate].
abstract class EditorTool {
  const EditorTool();

  /// Stable identifier used by the registry and shortcuts.
  String get id;

  String get label;

  /// Keyboard shortcut that activates this tool, or `null`.
  LogicalKeyboardKey? get shortcut => null;

  MouseCursor get cursor => SystemMouseCursors.basic;

  void activate(ToolContext context) {}

  void deactivate(ToolContext context) {}

  void onPointerDown(ToolContext context, ToolPointerEvent event) {}

  void onPointerMove(ToolContext context, ToolPointerEvent event) {}

  void onPointerUp(ToolContext context, ToolPointerEvent event) {}

  /// Handles a key press while active; returns true when consumed.
  bool onKey(ToolContext context, KeyEvent event) => false;

  /// Paints tool-specific overlay in *view* coordinates (§2.3 layer 2).
  void paintOverlay(Canvas canvas, Size size, ToolContext context) {}
}

/// Registry of available tools (§4.5: registration, never a switch).
final class ToolRegistry {
  ToolRegistry();

  final List<EditorTool> _tools = [];

  List<EditorTool> get tools => List.unmodifiable(_tools);

  void register(EditorTool tool) {
    assert(
      _tools.every((existing) => existing.id != tool.id),
      'Duplicate tool id: ${tool.id}',
    );
    _tools.add(tool);
  }

  EditorTool? byId(String id) {
    for (final tool in _tools) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  EditorTool? byShortcut(LogicalKeyboardKey key) {
    for (final tool in _tools) {
      if (tool.shortcut == key) return tool;
    }
    return null;
  }
}
