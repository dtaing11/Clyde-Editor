import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor_tool.dart';

/// Owns the registry and the active tool; notifies on switches.
///
/// Panels observe this to highlight the active tool, and the canvas
/// routes pointer events to [activeTool]. No other coupling exists
/// between toolbar and canvas.
final class ToolController extends ChangeNotifier {
  ToolController({required this.registry, required String initialToolId})
    : _activeTool = registry.byId(initialToolId) {
    assert(_activeTool != null, 'Unknown initial tool: $initialToolId');
  }

  final ToolRegistry registry;
  EditorTool? _activeTool;
  ToolContext? _context;

  EditorTool? get activeTool => _activeTool;

  /// Binds the canvas-provided context; called by the canvas when it
  /// mounts and unbinds on dispose.
  void attachContext(ToolContext? context) {
    _context = context;
  }

  void activate(String toolId) {
    final tool = registry.byId(toolId);
    final context = _context;
    if (tool == null || identical(tool, _activeTool)) return;
    if (context != null) {
      _activeTool?.deactivate(context);
      tool.activate(context);
    }
    _activeTool = tool;
    notifyListeners();
  }

  /// Activates the tool bound to [key]; returns true when one matched.
  bool activateByShortcut(LogicalKeyboardKey key) {
    final tool = registry.byShortcut(key);
    if (tool == null) return false;
    activate(tool.id);
    return true;
  }
}
