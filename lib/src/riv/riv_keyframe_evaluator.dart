import 'riv_document_model.dart';

/// Evaluates keyframe tracks at an arbitrary playhead time.
///
/// Mirrors the value semantics of the runtime's `KeyedProperty::apply`:
/// - before the first keyframe: the first keyframe's value
/// - after the last keyframe: the last keyframe's value
/// - between keyframes: interpolated according to the *left* keyframe's
///   interpolation type (hold keeps the left value, everything else is
///   approximated linearly for display purposes)
///
/// Cubic curves are shown with linear approximation for now; the
/// inspector labels those values as approximate.
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
      final t = (frame - left.frame) / (right.frame - left.frame);
      return left.value! + (right.value! - left.value!) * t;
    }
    return keyframes.last.value;
  }

  /// Whether the displayed value is exact ([RivInterpolationType.hold] or
  /// [RivInterpolationType.linear] segments) or a linear approximation of
  /// a cubic curve.
  static bool isApproximate(RivKeyedPropertyModel property) {
    return property.keyframes.any(
      (k) =>
          k.interpolation == RivInterpolationType.cubic ||
          k.interpolation == RivInterpolationType.cubicValue,
    );
  }
}
