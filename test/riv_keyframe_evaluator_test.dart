import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';
import 'package:rive_editor/src/riv/riv_keyframe_evaluator.dart';

RivKeyedPropertyModel _track(List<(int, double, RivInterpolationType)> keys) {
  final property = RivKeyedPropertyModel(propertyKey: 13);
  for (final (frame, value, interpolation) in keys) {
    property.keyframes.add(
      RivKeyFrameModel(
        frame: frame,
        interpolation: interpolation,
        value: value,
      ),
    );
  }
  return property;
}

void main() {
  group('RivKeyframeEvaluator', () {
    test('returns null for empty tracks', () {
      final property = RivKeyedPropertyModel(propertyKey: 13);
      expect(RivKeyframeEvaluator.evaluate(property, 0.5, 60), isNull);
    });

    test('clamps before first and after last keyframe', () {
      final track = _track([
        (30, 10, RivInterpolationType.linear),
        (60, 20, RivInterpolationType.linear),
      ]);
      // Before frame 30 (t < 0.5s at 60fps) -> first value.
      expect(RivKeyframeEvaluator.evaluate(track, 0.0, 60), 10);
      // After frame 60 (t > 1.0s) -> last value.
      expect(RivKeyframeEvaluator.evaluate(track, 2.0, 60), 20);
    });

    test('interpolates linearly between keyframes', () {
      final track = _track([
        (0, 0, RivInterpolationType.linear),
        (60, 100, RivInterpolationType.linear),
      ]);
      // Midpoint: frame 30 = 0.5s at 60fps -> exactly 50.
      expect(RivKeyframeEvaluator.evaluate(track, 0.5, 60), closeTo(50, 1e-6));
      // Quarter point -> exactly 25.
      expect(RivKeyframeEvaluator.evaluate(track, 0.25, 60), closeTo(25, 1e-6));
    });

    test('hold interpolation keeps left value until next key', () {
      final track = _track([
        (0, 5, RivInterpolationType.hold),
        (60, 50, RivInterpolationType.hold),
      ]);
      expect(RivKeyframeEvaluator.evaluate(track, 0.5, 60), 5);
      expect(RivKeyframeEvaluator.evaluate(track, 0.999, 60), 5);
      expect(RivKeyframeEvaluator.evaluate(track, 1.0, 60), 50);
    });

    test('multi-segment tracks pick the correct segment', () {
      final track = _track([
        (0, 0, RivInterpolationType.linear),
        (30, 30, RivInterpolationType.linear),
        (60, 0, RivInterpolationType.linear),
      ]);
      // Rising segment at 0.25s (frame 15) -> 15.
      expect(RivKeyframeEvaluator.evaluate(track, 0.25, 60), closeTo(15, 1e-6));
      // Falling segment at 0.75s (frame 45) -> 15.
      expect(RivKeyframeEvaluator.evaluate(track, 0.75, 60), closeTo(15, 1e-6));
      // Peak.
      expect(RivKeyframeEvaluator.evaluate(track, 0.5, 60), closeTo(30, 1e-6));
    });

    test('marks cubic tracks as approximate', () {
      final linear = _track([(0, 0, RivInterpolationType.linear)]);
      final cubic = _track([(0, 0, RivInterpolationType.cubic)]);
      expect(RivKeyframeEvaluator.isApproximate(linear), isFalse);
      expect(RivKeyframeEvaluator.isApproximate(cubic), isTrue);
    });
  });
}
