import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../state/editor_state.dart';
import 'editor_panel.dart';

/// Lists artboards and their animations for playback selection.
///
/// Structural scene content lives in [SceneHierarchyPanel]; this panel
/// is about *what plays* in the canvas and timeline.
class AnimationsPanel extends StatelessWidget {
  const AnimationsPanel({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final doc = state.document;
    return EditorPanel(
      title: 'Animations',
      child: doc == null
          ? const Center(
              child: Text(
                'No document',
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final artboard in doc.artboards) ...[
                  _AnimationsTile(
                    icon: Icons.crop_square,
                    label: artboard.name,
                    depth: 0,
                    selected: identical(artboard, state.activeArtboard),
                    onTap: () => state.selectArtboard(artboard),
                  ),
                  if (identical(artboard, state.activeArtboard))
                    for (var i = 0; i < state.animations.length; i++)
                      _AnimationsTile(
                        icon: Icons.play_circle_outline,
                        label: state.animations[i].name,
                        depth: 1,
                        selected: i == state.selectedAnimationIndex,
                        onTap: () => state.selectAnimation(i),
                      ),
                ],
              ],
            ),
    );
  }
}

class _AnimationsTile extends StatelessWidget {
  const _AnimationsTile({
    required this.icon,
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: EdgeInsets.only(left: 10.0 + depth * 18, right: 10),
        color: selected ? EditorTheme.accent.withValues(alpha: 0.18) : null,
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? EditorTheme.accent : EditorTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? EditorTheme.textPrimary
                      : EditorTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
