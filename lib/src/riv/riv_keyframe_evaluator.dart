import 'riv_document_model.dart';

/// Evaluates keyframe tracks at an arbitrary playhead time.
///
/// Mirrors the value semantics of the runtime's `KeyedProperty::apply`:
/// - before the first keyframe: the first keyframe's value
/// - after the last keyframe: the last keyframe's value
/// - between keyframes: interpolated according to the *left* keyframe's
///   interpolation type (hold keeps the left value; cubic keyframes with
///   a resolved [RivCubicEase] use the same bezier solver as the
///   runtime's `CubicInterpolatorSolver`; everything else is linear)
abstract final class RivKeyframeEvaluator {
  /// Value of [property] at [timeSeconds] in an animation running at
  /// [fps], or `null` when the track has no numeric keyframes.
  static double? evaluate(
    RivKeyedPropertyModel property,
    double timeSeconds,
    int fps,
  ) {
    final keyframes = property.keyframes.where((k) => k.value != null).toList();
    if (keyframes.isEmpty || fps <= 0) return null;

    final frame = timeSeconds * fps;
    if (frame <= keyframes.first.frame) return keyframes.first.value;
    if (frame >= keyframes.last.frame) return keyframes.last.value;

    // Find the segment [left, right] containing the frame.
    for (var i = 0; i < keyframes.length - 1; i++) {
      final left = keyframes[i];
      final right = keyframes[i + 1];
      if (frame < left.frame || frame > right.frame) continue;

      if (left.interpolation == RivInterpolationType.hold ||
          right.frame == left.frame) {
        return left.value;
      }
      var t = (frame - left.frame) / (right.frame - left.frame);
      final cubic = left.cubic;
      if ((left.interpolation == RivInterpolationType.cubic ||
              left.interpolation == RivInterpolationType.cubicValue) &&
          cubic != null) {
        t = _cubicEaseT(t, cubic);
      }
      return left.value! + (right.value! - left.value!) * t;
    }
    return keyframes.last.value;
  }

  /// Whether the displayed value is exact. Hold/linear segments always
  /// are; cubic segments are exact when their ease is resolved.
  static bool isApproximate(RivKeyedPropertyModel property) {
    return property.keyframes.any(
      (k) =>
          (k.interpolation == RivInterpolationType.cubic ||
              k.interpolation == RivInterpolationType.cubicValue) &&
          k.cubic == null,
    );
  }

  /// Maps linear progress [x] through the bezier ease, mirroring the
  /// runtime's `CubicInterpolatorSolver::getT` (Newton-Raphson with
  /// bisection fallback) so editor display matches playback exactly.
  static double _cubicEaseT(double x, RivCubicEase ease) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;

    double calcBezier(double t, double a1, double a2) =>
        (((1 - 3 * a2 + 3 * a1) * t + (3 * a2 - 6 * a1)) * t + 3 * a1) * t;
    double slope(double t, double a1, double a2) =>
        3 * (1 - 3 * a2 + 3 * a1) * t * t + 2 * (3 * a2 - 6 * a1) * t + 3 * a1;

    // Newton-Raphson from the linear guess.
    var guess = x;
    for (var i = 0; i < 8; i++) {
      final currentSlope = slope(guess, ease.x1, ease.x2);
      if (currentSlope < 0.001) break;
      final currentX = calcBezier(guess, ease.x1, ease.x2) - x;
      guess -= currentX / currentSlope;
    }
    if (guess >= 0 && guess <= 1) {
      final check = calcBezier(guess, ease.x1, ease.x2);
      if ((check - x).abs() < 1e-5) {
        return calcBezier(guess, ease.y1, ease.y2);
      }
    }

    // Bisection fallback for flat slopes.
    var lower = 0.0;
    var upper = 1.0;
    var t = x;
    for (var i = 0; i < 32; i++) {
      final currentX = calcBezier(t, ease.x1, ease.x2);
      if ((currentX - x).abs() < 1e-7) break;
      if (currentX > x) {
        upper = t;
      } else {
        lower = t;
      }
      t = (lower + upper) / 2;
    }
    return calcBezier(t, ease.y1, ease.y2);
  }

  /// Exposed for tests: raw bezier mapping.
  static double debugCubicEaseT(double x, RivCubicEase ease) =>
      _cubicEaseT(x, ease);
}
