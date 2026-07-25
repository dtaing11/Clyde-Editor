import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/editor_theme.dart';
import '../../core/tools/editor_tool.dart';
import '../../core/tools/tool_controller.dart';
import 'services/file_service.dart';
import 'state/editor_state.dart';
import 'tools/core_tools.dart';
import 'tools/shape_tools.dart';
import 'tools/text_tool.dart';
import 'widgets/canvas_panel.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/animations_panel.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/scene_hierarchy_panel.dart';
import 'widgets/timeline_panel.dart';
import 'widgets/tool_strip.dart';

/// Main editor screen.
///
/// Layout: toolbar on top; left dock with scene hierarchy over the
/// animations list; canvas in the center; inspector on the right;
/// timeline docked below. Global keyboard shortcuts are bound here.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorState _state;
  late final ToolController _toolController;
  final FileService _files = FileService();

  @override
  void initState() {
    super.initState();
    _state = EditorState();
    _toolController = ToolController(
      registry: ToolRegistry()
        ..register(SelectionTool())
        ..register(HandTool())
        ..register(const ZoomTool())
        ..register(RectangleTool())
        ..register(EllipseTool())
        ..register(PolygonTool())
        ..register(
          TextTool(
            fontProvider: const BundleFontProvider(),
            requestContent: _requestTextContent,
          ),
        ),
      initialToolId: SelectionTool.toolId,
    );
    // Start with a blank document; users create artboards on demand.
    _state.newDocument();
  }

  @override
  void dispose() {
    _toolController.dispose();
    _state.dispose();
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _state.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _state.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
        _state.redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        _state.redo,
    const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
        _state.newDocument(),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
        _state.newDocument(),
    const SingleActivator(LogicalKeyboardKey.space): _state.togglePlay,
    // Tool shortcuts resolve through the registry, not hard-coded ids.
    const SingleActivator(LogicalKeyboardKey.keyV): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyV),
    const SingleActivator(LogicalKeyboardKey.keyH): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyH),
    const SingleActivator(LogicalKeyboardKey.keyR): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyR),
    const SingleActivator(LogicalKeyboardKey.keyO): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyO),
    const SingleActivator(LogicalKeyboardKey.keyP): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyP),
    const SingleActivator(LogicalKeyboardKey.keyT): () =>
        _toolController.activateByShortcut(LogicalKeyboardKey.keyT),
  };

  /// Themed content prompt used by the Text tool.
  Future<String?> _requestTextContent() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Text'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(hintText: 'Enter text…'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: _state,
            builder: (context, _) {
              return Column(
                children: [
                  EditorToolbar(state: _state, files: _files),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: EditorTheme.sidePanelWidth,
                          child: Column(
                            children: [
                              Expanded(
                                flex: 3,
                                child: SceneHierarchyPanel(state: _state),
                              ),
                              Expanded(
                                flex: 2,
                                child: AnimationsPanel(state: _state),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        ToolStrip(controller: _toolController),
                        Expanded(
                          child: CanvasPanel(
                            state: _state,
                            toolController: _toolController,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: EditorTheme.sidePanelWidth,
                          child: InspectorPanel(state: _state),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: EditorTheme.timelineHeight,
                    child: TimelinePanel(state: _state),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
