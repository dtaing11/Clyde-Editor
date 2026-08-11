import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.siblingProperties = const [],
    this.onRetimeKeyframe,
    this.onSetKeyframeValue,
    this.onSetCubicEase,
    this.onTransformKeyframes,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;

  /// Other animated channels of the same object, overlaid read-only in
  /// per-channel colours behind the active curve (§2.8 multi-channel).
  final List<RivKeyedPropertyModel> siblingProperties;

  /// Per-channel colours, cycled by property-key hash so a channel
  /// keeps its colour across sessions.
  static const List<Color> channelColors = [
    Color(0xFFE57373), // red (X)
    Color(0xFF81C784), // green (Y)
    Color(0xFFBA68C8), // purple (rotation)
    Color(0xFF4DD0E1), // cyan (scale)
    Color(0xFFFFD54F), // amber (opacity)
  ];

  /// Stable colour for a channel by its Rive property key.
  static Color colorFor(int propertyKey) =>
      channelColors[propertyKey % channelColors.length];

  /// Invoked when a control point is dragged to a new frame.
  final void Function(RivKeyFrameModel keyframe, int newFrame)?
  onRetimeKeyframe;

  /// Invoked while a control point is dragged to a new value.
  final void Function(RivKeyFrameModel keyframe, double newValue)?
  onSetKeyframeValue;

  /// Invoked while a tangent handle of a cubic keyframe is dragged.
  final void Function(RivKeyFrameModel keyframe, RivCubicEase ease)?
  onSetCubicEase;

  /// Invoked while a box-selected group of keyframes is dragged; every
  /// entry carries the keyframe with its new absolute frame/value.
  final void Function(List<(RivKeyFrameModel, int, double)> moves)?
  onTransformKeyframes;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

/// Which tangent handle of a cubic segment is being dragged.
enum _HandleEnd { outgoing, incoming }

class _CurveEditorState extends State<CurveEditor> {
  static const double _hitRadius = 10;
  static const double _verticalPadding = 14;

  RivKeyFrameModel? _dragging;

  /// Cubic segment owner + which handle, when dragging a tangent.
  RivKeyFrameModel? _draggingHandleOf;
  _HandleEnd? _draggingHandleEnd;

  /// Box selection: raw indices of selected keyframes.
  final Set<int> _selected = {};

  /// Marquee rectangle while dragging on empty space, in view coords.
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  /// Group drag: pointer origin and each member's starting frame/value.
  Offset? _groupDragStart;
  Map<int, (int, double)>? _groupOrigins;

  /// When true the group drag scales frames around the group's first
  /// frame instead of translating (Alt/Option held at drag start).
  bool _groupScaling = false;

  List<RivKeyFrameModel> get _numericKeyframes => [
    for (final keyframe in widget.property.keyframes)
      if (keyframe.value != null) keyframe,
  ];

  /// Value range shown, padded so flat curves are not on the edge.
  /// Includes overlaid sibling channels so every curve fits the view.
  (double min, double max) get _valueRange {
    final keyframes = _numericKeyframes;
    if (keyframes.isEmpty) return (0, 1);
    var min = keyframes.first.value!;
    var max = min;
    void include(Iterable<RivKeyFrameModel> list) {
      for (final keyframe in list) {
        final value = keyframe.value;
        if (value == null) continue;
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }

    include(keyframes);
    for (final sibling in widget.siblingProperties) {
      if (identical(sibling, widget.property)) continue;
      include(sibling.keyframes);
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

  /// The keyframe following [keyframe] in the numeric list, or `null`.
  RivKeyFrameModel? _nextOf(RivKeyFrameModel keyframe) {
    final keyframes = _numericKeyframes;
    final index = keyframes.indexOf(keyframe);
    return index >= 0 && index < keyframes.length - 1
        ? keyframes[index + 1]
        : null;
  }

  /// View positions of both tangent handles for the cubic segment
  /// starting at [left], or `null` when the segment is not cubic.
  ({Offset outgoing, Offset incoming})? _handlePositions(
    RivKeyFrameModel left,
    Size size,
  ) {
    final cubic = left.cubic;
    final right = _nextOf(left);
    if (cubic == null || right == null) return null;
    final p0 = _pointFor(left, size);
    final p1 = _pointFor(right, size);
    return (
      outgoing: Offset(
        p0.dx + (p1.dx - p0.dx) * cubic.x1,
        p0.dy + (p1.dy - p0.dy) * cubic.y1,
      ),
      incoming: Offset(
        p0.dx + (p1.dx - p0.dx) * cubic.x2,
        p0.dy + (p1.dy - p0.dy) * cubic.y2,
      ),
    );
  }

  /// Hit test tangent handles of cubic segments.
  (RivKeyFrameModel, _HandleEnd)? _hitTestHandle(Offset local, Size size) {
    for (final keyframe in _numericKeyframes) {
      final handles = _handlePositions(keyframe, size);
      if (handles == null) continue;
      if ((handles.outgoing - local).distance < _hitRadius) {
        return (keyframe, _HandleEnd.outgoing);
      }
      if ((handles.incoming - local).distance < _hitRadius) {
        return (keyframe, _HandleEnd.incoming);
      }
    }
    return null;
  }

  void _applyHandleDrag(Offset local, Size size) {
    final owner = _draggingHandleOf;
    final end = _draggingHandleEnd;
    if (owner == null || end == null || widget.onSetCubicEase == null) return;
    final cubic = owner.cubic;
    final right = _nextOf(owner);
    if (cubic == null || right == null) return;

    final p0 = _pointFor(owner, size);
    final p1 = _pointFor(right, size);
    final dx = p1.dx - p0.dx;
    final dy = p1.dy - p0.dy;
    if (dx.abs() < 1e-6) return;

    // Normalise the pointer into segment space. x stays in [0,1] (the
    // runtime requires ease x in range); y may overshoot for bounce.
    final nx = ((local.dx - p0.dx) / dx).clamp(0.0, 1.0);
    final ny = dy.abs() < 1e-6 ? 0.0 : (local.dy - p0.dy) / dy;

    final ease = end == _HandleEnd.outgoing
        ? RivCubicEase(x1: nx, y1: ny, x2: cubic.x2, y2: cubic.y2)
        : RivCubicEase(x1: cubic.x1, y1: cubic.y1, x2: nx, y2: ny);
    widget.onSetCubicEase!(owner, ease);
  }

  void _finishMarquee(Size size) {
    final start = _marqueeStart;
    final end = _marqueeEnd;
    _marqueeStart = null;
    _marqueeEnd = null;
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start, end);
    if (rect.width < 3 && rect.height < 3) return;
    _selected
      ..clear()
      ..addAll([
        for (final keyframe in _numericKeyframes)
          if (rect.contains(_pointFor(keyframe, size))) keyframe.rawObjectIndex,
      ]);
  }

  void _applyGroupDrag(Offset local, Size size) {
    final start = _groupDragStart;
    final origins = _groupOrigins;
    if (start == null ||
        origins == null ||
        widget.onTransformKeyframes == null) {
      return;
    }
    final duration = widget.animation.durationFrames;
    if (duration <= 0) return;
    final (min, max) = _valueRange;
    final usable = size.height - 2 * _verticalPadding;
    if (usable <= 0) return;

    var lowest = duration;
    var highest = 0;
    for (final (frame, _) in origins.values) {
      if (frame < lowest) lowest = frame;
      if (frame > highest) highest = frame;
    }

    final moves = <(RivKeyFrameModel, int, double)>[];
    if (_groupScaling && highest > lowest) {
      // Scale frames around the group's first frame: horizontal drag
      // stretches the original span (§2.7 Scale keyframes).
      final pixelsPerFrame = size.width / duration;
      final spanPixels = (highest - lowest) * pixelsPerFrame;
      if (spanPixels <= 0) return;
      final factor = ((spanPixels + (local.dx - start.dx)) / spanPixels).clamp(
        0.0,
        (duration - lowest) / (highest - lowest),
      );
      for (final keyframe in _numericKeyframes) {
        final origin = origins[keyframe.rawObjectIndex];
        if (origin == null) continue;
        final scaled = lowest + ((origin.$1 - lowest) * factor).round();
        moves.add((keyframe, scaled.clamp(0, duration), origin.$2));
      }
    } else {
      var deltaFrames = (((local.dx - start.dx) / size.width) * duration)
          .round();
      final deltaValue = -((local.dy - start.dy) / usable) * (max - min);
      // Clamp the delta so the whole group stays inside [0, dur].
      deltaFrames = deltaFrames.clamp(-lowest, duration - highest);
      for (final keyframe in _numericKeyframes) {
        final origin = origins[keyframe.rawObjectIndex];
        if (origin == null) continue;
        moves.add((keyframe, origin.$1 + deltaFrames, origin.$2 + deltaValue));
      }
    }
    if (moves.isNotEmpty) widget.onTransformKeyframes!(moves);
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
    // Document edits rebuild the model; re-resolve dragged objects by
    // raw index so drags survive across rebuilds.
    final dragging = _dragging;
    if (dragging != null) {
      _dragging = _numericKeyframes
          .where((k) => k.rawObjectIndex == dragging.rawObjectIndex)
          .firstOrNull;
    }
    final handleOwner = _draggingHandleOf;
    if (handleOwner != null) {
      _draggingHandleOf = _numericKeyframes
          .where((k) => k.rawObjectIndex == handleOwner.rawObjectIndex)
          .firstOrNull;
    }
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
            final handle = widget.onSetCubicEase == null
                ? null
                : _hitTestHandle(details.localPosition, size);
            if (handle != null) {
              setState(() {
                _draggingHandleOf = handle.$1;
                _draggingHandleEnd = handle.$2;
              });
              return;
            }
            final hit = _hitTest(details.localPosition, size);
            if (hit != null) {
              // Dragging a selected point moves the whole selection.
              if (_selected.contains(hit.rawObjectIndex) &&
                  _selected.length > 1 &&
                  widget.onTransformKeyframes != null) {
                setState(() {
                  _groupDragStart = details.localPosition;
                  _groupScaling = HardwareKeyboard.instance.isAltPressed;
                  _groupOrigins = {
                    for (final keyframe in _numericKeyframes)
                      if (_selected.contains(keyframe.rawObjectIndex))
                        keyframe.rawObjectIndex: (
                          keyframe.frame,
                          keyframe.value!,
                        ),
                  };
                });
                return;
              }
              setState(() {
                _selected.clear();
                _dragging = hit;
              });
              return;
            }
            // Empty space: begin a marquee.
            setState(() {
              _selected.clear();
              _marqueeStart = details.localPosition;
              _marqueeEnd = details.localPosition;
            });
          },
          onPanUpdate: (details) {
            if (_draggingHandleOf != null) {
              _applyHandleDrag(details.localPosition, size);
            } else if (_groupDragStart != null) {
              _applyGroupDrag(details.localPosition, size);
            } else if (_marqueeStart != null) {
              setState(() => _marqueeEnd = details.localPosition);
            } else {
              _applyDrag(details.localPosition, size);
            }
          },
          onPanEnd: (_) => setState(() {
            _finishMarquee(size);
            _dragging = null;
            _draggingHandleOf = null;
            _draggingHandleEnd = null;
            _groupDragStart = null;
            _groupOrigins = null;
            _groupScaling = false;
          }),
          onPanCancel: () => setState(() {
            _marqueeStart = null;
            _marqueeEnd = null;
            _dragging = null;
            _draggingHandleOf = null;
            _draggingHandleEnd = null;
            _groupDragStart = null;
            _groupOrigins = null;
            _groupScaling = false;
          }),
          child: CustomPaint(
            size: size,
            painter: _CurvePainter(
              property: widget.property,
              animation: widget.animation,
              siblingProperties: widget.siblingProperties,
              valueRange: _valueRange,
              verticalPadding: _verticalPadding,
              dragging: _dragging,
              showHandles: widget.onSetCubicEase != null,
              selectedIndices: Set.of(_selected),
              marquee: _marqueeStart != null && _marqueeEnd != null
                  ? Rect.fromPoints(_marqueeStart!, _marqueeEnd!)
                  : null,
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
    required this.siblingProperties,
    required this.valueRange,
    required this.verticalPadding,
    required this.dragging,
    required this.showHandles,
    required this.selectedIndices,
    required this.marquee,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;
  final List<RivKeyedPropertyModel> siblingProperties;
  final (double, double) valueRange;
  final double verticalPadding;
  final RivKeyFrameModel? dragging;
  final bool showHandles;
  final Set<int> selectedIndices;
  final Rect? marquee;

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

    // Evaluated curves: one sample per horizontal pixel through the
    // shared evaluator (same code path as inspector values, §2.8).
    // Sibling channels draw dimmed behind the active curve, each in
    // its per-channel colour.
    final duration = animation.durationFrames;
    if (duration > 0) {
      for (final sibling in siblingProperties) {
        if (identical(sibling, property) ||
            sibling.propertyKey == property.propertyKey) {
          continue;
        }
        _paintCurve(
          canvas,
          size,
          sibling,
          CurveEditor.colorFor(sibling.propertyKey).withValues(alpha: 0.45),
          1,
        );
      }
      _paintCurve(
        canvas,
        size,
        property,
        CurveEditor.colorFor(property.propertyKey),
        1.8,
      );
    }

    // Tangent handles for cubic segments: stems + squares at the
    // bezier control points, in segment space.
    if (showHandles && duration > 0) {
      final numeric = [
        for (final k in property.keyframes)
          if (k.value != null) k,
      ];
      final stem = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.textSecondary;
      final handleFill = Paint()..color = const Color(0xFFFFB74D);
      for (var i = 0; i < numeric.length - 1; i++) {
        final left = numeric[i];
        final right = numeric[i + 1];
        final cubic = left.cubic;
        if (cubic == null) continue;
        final p0 = Offset(
          (left.frame / duration) * size.width,
          _yFor(left.value!, size),
        );
        final p1 = Offset(
          (right.frame / duration) * size.width,
          _yFor(right.value!, size),
        );
        final outgoing = Offset(
          p0.dx + (p1.dx - p0.dx) * cubic.x1,
          p0.dy + (p1.dy - p0.dy) * cubic.y1,
        );
        final incoming = Offset(
          p0.dx + (p1.dx - p0.dx) * cubic.x2,
          p0.dy + (p1.dy - p0.dy) * cubic.y2,
        );
        canvas.drawLine(p0, outgoing, stem);
        canvas.drawLine(p1, incoming, stem);
        for (final handle in [outgoing, incoming]) {
          canvas.drawRect(
            Rect.fromCenter(center: handle, width: 7, height: 7),
            handleFill,
          );
        }
      }
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
              keyframe.rawObjectIndex == dragging!.rawObjectIndex) ||
          selectedIndices.contains(keyframe.rawObjectIndex);
      canvas.drawCircle(
        centre,
        isDragging ? 6 : 4.5,
        Paint()
          ..color = isDragging
              ? Colors.white
              : CurveEditor.colorFor(property.propertyKey),
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

    final marqueeRect = marquee;
    if (marqueeRect != null) {
      canvas.drawRect(
        marqueeRect,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0x2257A5FF),
      );
      canvas.drawRect(
        marqueeRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = EditorTheme.accent,
      );
    }
  }

  void _paintCurve(
    Canvas canvas,
    Size size,
    RivKeyedPropertyModel track,
    Color color,
    double strokeWidth,
  ) {
    final path = Path();
    var started = false;
    for (var x = 0.0; x <= size.width; x += 1) {
      final seconds =
          (x / size.width) * animation.durationFrames / animation.fps;
      final value = RivKeyframeEvaluator.evaluate(
        track,
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
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) => true;
}
