import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';
import 'package:rive_editor/src/riv/riv_keyframe_evaluator.dart';

/// §2.7 acceptance: scrubbing 10,000 keyframes stays at 60 fps.
///
/// Scrubbing evaluates every animated track at the playhead. The 60 fps
/// budget is ~16 ms per frame; evaluation must use a small fraction of
/// it. This benchmark evaluates a 10k-keyframe track at 1,000 distinct
/// playhead positions (a full scrub sweep) and requires the whole sweep
/// to finish well inside one frame budget, best-of-5 to reject CI
/// scheduling noise.
void main() {
  RivKeyedPropertyModel bigTrack(int count) {
    final property = RivKeyedPropertyModel(propertyKey: 13);
    for (var i = 0; i < count; i++) {
      property.keyframes.add(
        RivKeyFrameModel(
          frame: i,
          interpolation: i.isEven
              ? RivInterpolationType.linear
              : RivInterpolationType.hold,
          value: (i % 100).toDouble(),
          rawObjectIndex: i,
        ),
      );
    }
    return property;
  }

  test('scrub sweep over 10k keyframes stays inside the frame budget', () {
    final property = bigTrack(10000);
    const fps = 60;
    const sweepSamples = 1000;
    final durationSeconds = 10000 / fps;

    // Warm-up builds the numeric cache and JIT-compiles the path.
    for (var i = 0; i < sweepSamples; i++) {
      RivKeyframeEvaluator.evaluate(
        property,
        durationSeconds * i / sweepSamples,
        fps,
      );
    }

    var bestMicros = double.infinity;
    for (var run = 0; run < 5; run++) {
      final stopwatch = Stopwatch()..start();
      var checksum = 0.0;
      for (var i = 0; i < sweepSamples; i++) {
        checksum +=
            RivKeyframeEvaluator.evaluate(
              property,
              durationSeconds * i / sweepSamples,
              fps,
            ) ??
            0;
      }
      stopwatch.stop();
      expect(checksum, isNot(double.nan));
      if (stopwatch.elapsedMicroseconds < bestMicros) {
        bestMicros = stopwatch.elapsedMicroseconds.toDouble();
      }
    }

    // 1,000 playhead evaluations across 10k keyframes in under 8 ms
    // (half the 60 fps frame budget): one scrub tick evaluates a
    // handful of tracks, so per-track cost must be tiny.
    expect(
      bestMicros,
      lessThan(8000),
      reason:
          'best-of-5 sweep took ${bestMicros / 1000}ms; '
          'binary search should keep this well under the frame budget',
    );
  });

  test('cache invalidation keeps evaluation correct after edits', () {
    final property = bigTrack(100);
    final before = RivKeyframeEvaluator.evaluate(property, 0.5, 60);
    expect(before, isNotNull);

    // Simulate an in-place edit + invalidation.
    property.keyframes.removeRange(0, 50);
    property.invalidateCache();
    final after = RivKeyframeEvaluator.evaluate(property, 0.5, 60);
    expect(after, property.keyframes.first.value);
  });
}
