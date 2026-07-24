import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../core/theme/editor_theme.dart';
import '../state/editor_state.dart';

/// Center canvas that renders the active artboard with the Rive Renderer.
class ViewportPanel extends StatelessWidget {
  const ViewportPanel({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final artboard = state.activeArtboard;
    return ColoredBox(
      color: EditorTheme.viewportBackground,
      child: artboard == null
          ? const _EmptyViewport()
          : Padding(
              padding: const EdgeInsets.all(24),
              child: rive.RiveArtboardWidget(
                artboard: artboard,
                painter: state.painter,
              ),
            ),
    );
  }
}

class _EmptyViewport extends StatelessWidget {
  const _EmptyViewport();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.animation, size: 48, color: EditorTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            'Open a .riv file to start editing',
            style: TextStyle(color: EditorTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
