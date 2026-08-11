import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_document_model.dart';
import '../../../riv/riv_keyframe_evaluator.dart';

/// Curve editor for one animated property (§2.8).
///
/// Plots value against time using [RivKeyframeEvaluator] — the same
/// code path the inspector uses to display evaluated values — and lets
/// the user drag control points: horizontally to retime (clamped
/// between neighbours so keyframes can never cross, per acceptance)
/// and vertically to change the value.
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    super.key,
    required this.property,
    required this.animation,
    this.onRetimeKeyframe,
    this.onSetKeyframeValue,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;

  /// Invoked when a control point is dragged to a new frame.
  final void Function(RivKeyFrameModel keyframe, int newFrame)?
  onRetimeKeyframe;

  /// Invoked while a control point is dragged to a new value.
  final void Function(RivKeyFrameModel keyframe, double newValue)?
  onSetKeyframeValue;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  static const double _hitRadius = 10;
  static const double _verticalPadding = 14;

  RivKeyFrameModel? _dragging;

  List<RivKeyFrameModel> get _numericKeyframes => [
    for (final keyframe in widget.property.keyframes)
      if (keyframe.value != null) keyframe,
  ];

  /// Value range shown, padded so flat curves are not on the edge.
  (double min, double max) get _valueRange {
    final keyframes = _numericKeyframes;
    if (keyframes.isEmpty) return (0, 1);
    var min = keyframes.first.value!;
    var max = min;
    for (final keyframe in keyframes) {
      final value = keyframe.value!;
      if (value < min) min = value;
      if (value > max) max = value;
    }
    if (min == max) {
      min -= 1;
      max += 1;
    }
    final pad = (max - min) * 0.1;
    return (min - pad, max + pad);
  }

  Offset _pointFor(RivKeyFrameModel keyframe, Size size) {
    final (min, max) = _valueRange;
    final duration = widget.animation.durationFrames;
    final x = duration > 0 ? (keyframe.frame / duration) * size.width : 0.0;
    final t = (keyframe.value! - min) / (max - min);
    final y =
        size.height -
        _verticalPadding -
        t * (size.height - 2 * _verticalPadding);
    return Offset(x, y);
  }

  RivKeyFrameModel? _hitTest(Offset local, Size size) {
    RivKeyFrameModel? closest;
    var closestDistance = double.infinity;
    for (final keyframe in _numericKeyframes) {
      final distance = (_pointFor(keyframe, size) - local).distance;
      if (distance < _hitRadius && distance < closestDistance) {
        closest = keyframe;
        closestDistance = distance;
      }
    }
    return closest;
  }

  void _applyDrag(Offset local, Size size) {
    final dragging = _dragging;
    if (dragging == null) return;

    final duration = widget.animation.durationFrames;
    final (min, max) = _valueRange;

    // Horizontal: clamp between neighbours (time-monotonicity, §2.8).
    if (widget.onRetimeKeyframe != null && duration > 0) {
      final keyframes = _numericKeyframes;
      final index = keyframes.indexOf(dragging);
      final lowerBound = index > 0 ? keyframes[index - 1].frame + 1 : 0;
      final upperBound = index >= 0 && index < keyframes.length - 1
          ? keyframes[index + 1].frame - 1
          : duration;
      final frame = ((local.dx / size.width) * duration).round().clamp(
        lowerBound,
        upperBound,
      );
      if (frame != dragging.frame) {
        widget.onRetimeKeyframe!(dragging, frame);
      }
    }

    // Vertical: map back to value space.
    if (widget.onSetKeyframeValue != null) {
      final usable = size.height - 2 * _verticalPadding;
      if (usable > 0) {
        final t = ((size.height - _verticalPadding - local.dy) / usable).clamp(
          0.0,
          1.0,
        );
        final value = min + t * (max - min);
        if (value != dragging.value) {
          widget.onSetKeyframeValue!(dragging, value);
        }
      }
    }
  }

  @override
  void didUpdateWidget(CurveEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Document edits rebuild the model; re-resolve the dragged keyframe
    // by raw index so the drag survives across rebuilds.
    final dragging = _dragging;
    if (dragging == null) return;
    _dragging = _numericKeyframes
        .where((k) => k.rawObjectIndex == dragging.rawObjectIndex)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    if (_numericKeyframes.length < 2) {
      return const Center(
        child: Text(
          'At least two keyframes are needed to edit a curve',
          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final hit = _hitTest(details.localPosition, size);
            if (hit != null) setState(() => _dragging = hit);
          },
          onPanUpdate: (details) => _applyDrag(details.localPosition, size),
          onPanEnd: (_) => setState(() => _dragging = null),
          onPanCancel: () => setState(() => _dragging = null),
          child: CustomPaint(
            size: size,
            painter: _CurvePainter(
              property: widget.property,
              animation: widget.animation,
              valueRange: _valueRange,
              verticalPadding: _verticalPadding,
              dragging: _dragging,
            ),
          ),
        );
      },
    );
  }
}

/// Paints the evaluated curve, control points, and value grid.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.property,
    required this.animation,
    required this.valueRange,
    required this.verticalPadding,
    required this.dragging,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;
  final (double, double) valueRange;
  final double verticalPadding;
  final RivKeyFrameModel? dragging;

  double _yFor(double value, Size size) {
    final (min, max) = valueRange;
    final t = (value - min) / (max - min);
    return size.height -
        verticalPadding -
        t * (size.height - 2 * verticalPadding);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.viewportBackground,
    );

    final (min, max) = valueRange;
    final labelStyle = const TextStyle(
      fontSize: 9,
      color: EditorTheme.textSecondary,
    );
    // Min/max gridlines with labels.
    for (final value in [min, max]) {
      final y = _yFor(value, size);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = EditorTheme.border
          ..strokeWidth = 1,
      );
      final painter = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(1), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(4, y - painter.height - 2));
    }

    // Evaluated curve: one sample per horizontal pixel through the
    // shared evaluator (same code path as inspector values, §2.8).
    final duration = animation.durationFrames;
    if (duration > 0) {
      final path = Path();
      var started = false;
      for (var x = 0.0; x <= size.width; x += 1) {
        final seconds = (x / size.width) * duration / animation.fps;
        final value = RivKeyframeEvaluator.evaluate(
          property,
          seconds,
          animation.fps,
        );
        if (value == null) continue;
        final y = _yFor(value, size);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = EditorTheme.accent,
      );
    }

    // Control points.
    for (final keyframe in property.keyframes) {
      final value = keyframe.value;
      if (value == null || duration <= 0) continue;
      final centre = Offset(
        (keyframe.frame / duration) * size.width,
        _yFor(value, size),
      );
      final isDragging =
          identical(keyframe, dragging) ||
          (dragging != null &&
              keyframe.rawObjectIndex == dragging!.rawObjectIndex);
      canvas.drawCircle(
        centre,
        isDragging ? 6 : 4.5,
        Paint()..color = isDragging ? Colors.white : EditorTheme.accent,
      );
      canvas.drawCircle(
        centre,
        isDragging ? 6 : 4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = EditorTheme.background,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) => true;
}
