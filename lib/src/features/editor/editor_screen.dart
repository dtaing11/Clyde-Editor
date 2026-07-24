import 'package:flutter/material.dart';

import '../../core/theme/editor_theme.dart';
import 'state/editor_state.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/hierarchy_panel.dart';
import 'widgets/timeline_panel.dart';
import 'widgets/viewport_panel.dart';

/// Main editor screen: toolbar on top, hierarchy on the left,
/// viewport in the center and timeline docked at the bottom.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorState _state;

  @override
  void initState() {
    super.initState();
    _state = EditorState();
    // Load a bundled demo so the editor is never empty on first launch.
    _state.loadFromAsset('assets/demo/little_machine.riv');
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          return Column(
            children: [
              EditorToolbar(state: _state),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: EditorTheme.sidePanelWidth,
                      child: HierarchyPanel(state: _state),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: ViewportPanel(state: _state)),
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
    );
  }
}
