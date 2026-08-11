import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';
import 'package:rive_editor/src/features/editor/widgets/curve_editor.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';

RivAnimationModel _animation({List<(int, double)> keys = const []}) {
  final animation = RivAnimationModel(name: 'A', fps: 60, durationFrames: 60);
  final keyed = RivKeyedObjectModel(objectId: 1, objectName: 'Shape');
  final property = RivKeyedPropertyModel(propertyKey: 13);
  for (final (i, (frame, value)) in keys.indexed) {
    property.keyframes.add(
      RivKeyFrameModel(
        frame: frame,
        interpolation: RivInterpolationType.linear,
        value: value,
        rawObjectIndex: 100 + i,
      ),
    );
  }
  keyed.properties.add(property);
  animation.keyedObjects.add(keyed);
  return animation;
}

void main() {
  Future<RivAnimationModel> pump(
    WidgetTester tester, {
    required List<(int, double)> keys,
    void Function(RivKeyFrameModel, int)? onRetime,
    void Function(RivKeyFrameModel, double)? onSetValue,
  }) async {
    final animation = _animation(keys: keys);
    await tester.pumpWidget(
      MaterialApp(
        theme: EditorTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: CurveEditor(
              property: animation.keyedObjects.single.properties.single,
              animation: animation,
              onRetimeKeyframe: onRetime,
              onSetKeyframeValue: onSetValue,
            ),
          ),
        ),
      ),
    );
    return animation;
  }

  testWidgets('fewer than two keyframes shows the empty message', (
    tester,
  ) async {
    await pump(tester, keys: [(0, 10)]);
    expect(
      find.text('At least two keyframes are needed to edit a curve'),
      findsOneWidget,
    );
  });

  testWidgets('dragging the middle point right clamps before its neighbour', (
    tester,
  ) async {
    final retimes = <(int keyframeIndex, int frame)>[];
    final animation = await pump(
      tester,
      keys: [(0, 0), (30, 50), (60, 100)],
      onRetime: (keyframe, frame) =>
          retimes.add((keyframe.rawObjectIndex, frame)),
      onSetValue: (_, _) {},
    );
    expect(animation, isNotNull);

    final surface = tester.getRect(find.byType(CustomPaint).last);
    // Middle keyframe (frame 30) sits at the horizontal centre.
    final start = Offset(surface.left + surface.width * 0.5, surface.center.dy);
    final gesture = await tester.startGesture(start);
    // Drag far right, well past the frame-60 neighbour.
    await gesture.moveBy(Offset(surface.width, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(retimes, isNotEmpty);
    final (index, frame) = retimes.last;
    expect(index, 101, reason: 'the middle keyframe must be the drag target');
    expect(
      frame,
      lessThan(60),
      reason: 'time-monotonicity: cannot cross the frame-60 neighbour',
    );
    expect(frame, 59, reason: 'clamps to neighbour frame minus one');
  });

  testWidgets('vertical drags report new values within the padded range', (
    tester,
  ) async {
    final values = <double>[];
    await pump(
      tester,
      keys: [(0, 0), (60, 100)],
      onRetime: (_, _) {},
      onSetValue: (_, value) => values.add(value),
    );

    final surface = tester.getRect(find.byType(CustomPaint).last);
    // First keyframe (frame 0, value 0): the padded value range is
    // [-10, 110], so value 0 sits at t = 10/120 of the usable height
    // (14px vertical padding) above the bottom.
    const pad = 14.0;
    final usable = surface.height - 2 * pad;
    final y = surface.bottom - pad - (10 / 120) * usable;
    final start = Offset(surface.left + 1, y);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isNotEmpty);
    expect(
      values.last,
      greaterThan(0),
      reason: 'dragging up must increase the value',
    );
  });
}
