import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../state/editor_state.dart';
import 'editor_panel.dart';
import 'keyframe_track_list.dart';

/// Bottom timeline: transport controls, time ruler with scrubbing, and
/// keyframe tracks parsed from the `.riv` file.
class TimelinePanel extends StatelessWidget {
  const TimelinePanel({super.key, required this.state});

  final EditorState state;

  /// Width of the left gutter holding track names; the ruler and track
  /// rows share it so keyframe diamonds line up with tick marks.
  static const double labelGutterWidth = 160;

  @override
  Widget build(BuildContext context) {
    final animation = state.selectedAnimation;
    final model = state.selectedAnimationModel;
    return EditorPanel(
      title: 'Timeline',
      actions: [
        if (animation != null) ...[
          _TimeUnitToggle(state: state),
          const SizedBox(width: 10),
          Text(
            '${state.formatTime(state.currentTime)} / '
            '${state.formatTime(state.duration)}',
            style: const TextStyle(
              fontSize: 11,
              color: EditorTheme.textSecondary,
            ),
          ),
        ],
      ],
      child: animation == null
          ? const Center(
              child: Text(
                'Select an animation',
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            )
          : Column(
              children: [
                _TransportBar(state: state),
                const Divider(height: 1),
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      const SizedBox(width: labelGutterWidth),
                      Expanded(child: _ScrubberRuler(state: state)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: model == null
                      ? const Center(
                          child: Text(
                            'Keyframe data unavailable for this file',
                            style: TextStyle(
                              color: EditorTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : KeyframeTrackList(
                          animation: model,
                          labelWidth: labelGutterWidth,
                          selectedKeyedObject: state.selectedKeyedObject,
                          onSelectKeyedObject: state.selectKeyedObject,
                          onRetimeKeyframe: state.canEdit
                              ? (keyframe, newFrame) =>
                                    state.retimeKeyframe(keyframe, newFrame)
                              : null,
                        ),
                ),
              ],
            ),
    );
  }
}

/// Segmented toggle switching time display between frames and seconds.
class _TimeUnitToggle extends StatelessWidget {
  const _TimeUnitToggle({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeUnitButton(
            label: 'f',
            tooltip: 'Show frames',
            selected: state.timeDisplayMode == TimeDisplayMode.frames,
            onTap: () => state.setTimeDisplayMode(TimeDisplayMode.frames),
          ),
          _TimeUnitButton(
            label: 's',
            tooltip: 'Show seconds',
            selected: state.timeDisplayMode == TimeDisplayMode.seconds,
            onTap: () => state.setTimeDisplayMode(TimeDisplayMode.seconds),
          ),
        ],
      ),
    );
  }
}

class _TimeUnitButton extends StatelessWidget {
  const _TimeUnitButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: selected
              ? EditorTheme.accent.withValues(alpha: 0.25)
              : Colors.transparent,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? EditorTheme.accent : EditorTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: 'Go to start',
            icon: const Icon(Icons.skip_previous),
            onPressed: () => state.seek(0),
          ),
          IconButton(
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            tooltip: state.isPlaying ? 'Pause' : 'Play',
            color: EditorTheme.accent,
            icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: state.togglePlay,
          ),
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: 'Go to end',
            icon: const Icon(Icons.skip_next),
            onPressed: () => state.seek(state.duration),
          ),
          const SizedBox(width: 12),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Undo edit',
            icon: const Icon(Icons.undo),
            onPressed: state.canUndo ? state.undo : null,
          ),
        ],
      ),
    );
  }
}

/// Time ruler with a draggable playhead.
class _ScrubberRuler extends StatelessWidget {
  const _ScrubberRuler({required this.state});

  final EditorState state;

  void _seekFromPosition(BuildContext context, Offset localPosition) {
    final box = context.findRenderObject() as RenderBox;
    if (box.size.width <= 0 || state.duration <= 0) return;
    final t = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
    state.seek(t * state.duration);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _seekFromPosition(context, d.localPosition),
      onHorizontalDragUpdate: (d) =>
          _seekFromPosition(context, d.localPosition),
      child: CustomPaint(
        size: Size.infinite,
        painter: _TimelineRulerPainter(
          duration: state.duration,
          currentTime: state.currentTime,
          fps: state.fps,
          displayMode: state.timeDisplayMode,
        ),
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  _TimelineRulerPainter({
    required this.duration,
    required this.currentTime,
    required this.fps,
    required this.displayMode,
  });

  final double duration;
  final double currentTime;
  final int fps;
  final TimeDisplayMode displayMode;

  /// Picks a label step so labels stay readable at any zoom: the
  /// smallest "nice" step at least [minStep].
  static double _niceStep(double minStep) {
    const steps = [1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000];
    for (final step in steps) {
      if (step >= minStep) return step.toDouble();
    }
    return 1000;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = EditorTheme.timelineTrack,
    );

    if (duration <= 0 || fps <= 0) return;

    final tickPaint = Paint()
      ..color = EditorTheme.border
      ..strokeWidth = 1;
    final textStyle = TextStyle(
      color: EditorTheme.textSecondary.withValues(alpha: 0.8),
      fontSize: 9,
    );

    final totalFrames = duration * fps;
    // Aim for a label roughly every 60px and a tick every 8px.
    final labelStepFrames = _niceStep(totalFrames * 60 / size.width);
    final tickStepFrames = _niceStep(totalFrames * 8 / size.width);

    for (var f = 0.0; f <= totalFrames + 1e-6; f += tickStepFrames) {
      final x = (f / totalFrames) * size.width;
      final isMajor = f % labelStepFrames < 1e-6;
      canvas.drawLine(
        Offset(x, isMajor ? 6 : 14),
        Offset(x, size.height),
        tickPaint,
      );
      if (isMajor) {
        final label = displayMode == TimeDisplayMode.frames
            ? '${f.round()}f'
            : '${(f / fps).toStringAsFixed(2)}s';
        final tp = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
      }
    }

    // Playhead.
    final playheadX = (currentTime / duration) * size.width;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = EditorTheme.playhead
        ..strokeWidth = 1.5,
    );
    final headPath = Path()
      ..moveTo(playheadX - 5, 0)
      ..lineTo(playheadX + 5, 0)
      ..lineTo(playheadX, 8)
      ..close();
    canvas.drawPath(headPath, Paint()..color = EditorTheme.playhead);
  }

  @override
  bool shouldRepaint(_TimelineRulerPainter oldDelegate) =>
      oldDelegate.currentTime != currentTime ||
      oldDelegate.duration != duration ||
      oldDelegate.fps != fps ||
      oldDelegate.displayMode != displayMode;
}
