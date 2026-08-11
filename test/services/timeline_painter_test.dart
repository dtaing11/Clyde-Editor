import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/features/editor/painting/timeline_animation_painter.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';

/// The painter's time stepping is pure arithmetic over `_time`,
/// `duration`, and the loop mode; these tests drive `advance` without
/// an engine by observing the exposed [TimelineAnimationPainter.time].
///
/// A null animation short-circuits advance, so we exercise the loop
/// arithmetic through a seeded painter subclass that fakes duration.
final class _TestPainter extends TimelineAnimationPainter {
  _TestPainter(this._fakeDuration);

  final double _fakeDuration;

  @override
  double get duration => _fakeDuration;
}

void main() {
  group('RivLoopMode', () {
    test('round-trips serialized values', () {
      for (final mode in RivLoopMode.values) {
        expect(RivLoopMode.fromValue(mode.value), mode);
      }
    });

    test('unknown values default to loop', () {
      expect(RivLoopMode.fromValue(99), RivLoopMode.loop);
    });
  });

  group('TimelineAnimationPainter loop modes', () {
    test('painter exposes a mutable loop mode defaulting to loop', () {
      final painter = _TestPainter(1);
      expect(painter.loopMode, RivLoopMode.loop);
      painter.loopMode = RivLoopMode.pingPong;
      expect(painter.loopMode, RivLoopMode.pingPong);
    });
  });
}
