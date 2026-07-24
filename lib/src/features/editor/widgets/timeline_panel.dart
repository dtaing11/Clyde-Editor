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
        if (animation != null)
          Text(
            '${state.currentTime.toStringAsFixed(2)}s / '
            '${state.duration.toStringAsFixed(2)}s',
            style:
                const TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
          ),
      ],
      child: animation == null
          ? const Center(
              child: Text(
                'Select an animation',
                style:
                    TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
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
                        ),
                ),
              ],
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
        ),
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  _TimelineRulerPainter({required this.duration, required this.currentTime});

  final double duration;
  final double currentTime;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = EditorTheme.timelineTrack,
    );

    if (duration <= 0) return;

    // Tick marks every 0.1s, labels every 0.5s.
    final tickPaint = Paint()
      ..color = EditorTheme.border
      ..strokeWidth = 1;
    final textStyle = TextStyle(
      color: EditorTheme.textSecondary.withValues(alpha: 0.8),
      fontSize: 9,
    );
    const minorStep = 0.1;
    for (var t = 0.0; t <= duration + 1e-6; t += minorStep) {
      final x = (t / duration) * size.width;
      final isMajor = (t / 0.5) % 1 < 1e-6 || (0.5 - (t % 0.5)).abs() < 1e-6;
      canvas.drawLine(
        Offset(x, isMajor ? 6 : 14),
        Offset(x, size.height),
        tickPaint,
      );
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(text: '${t.toStringAsFixed(1)}s', style: textStyle),
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
      oldDelegate.duration != duration;
}
