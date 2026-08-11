import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';
import 'package:rive_editor/src/features/editor/widgets/curve_editor.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';

RivAnimationModel _multiChannelAnimation() {
  final animation = RivAnimationModel(name: 'A', fps: 60, durationFrames: 60);
  final keyed = RivKeyedObjectModel(objectId: 1, objectName: 'Shape');
  for (final (key, values) in [(13, (0.0, 100.0)), (14, (500.0, 900.0))]) {
    final property = RivKeyedPropertyModel(propertyKey: key);
    property.keyframes.addAll([
      RivKeyFrameModel(
        frame: 0,
        interpolation: RivInterpolationType.linear,
        value: values.$1,
        rawObjectIndex: 200 + key,
      ),
      RivKeyFrameModel(
        frame: 60,
        interpolation: RivInterpolationType.linear,
        value: values.$2,
        rawObjectIndex: 300 + key,
      ),
    ]);
    keyed.properties.add(property);
  }
  animation.keyedObjects.add(keyed);
  return animation;
}

RivAnimationModel _animation({
  List<(int, double)> keys = const [],
  RivCubicEase? firstKeyCubic,
}) {
  final animation = RivAnimationModel(name: 'A', fps: 60, durationFrames: 60);
  final keyed = RivKeyedObjectModel(objectId: 1, objectName: 'Shape');
  final property = RivKeyedPropertyModel(propertyKey: 13);
  for (final (i, (frame, value)) in keys.indexed) {
    final keyframe = RivKeyFrameModel(
      frame: frame,
      interpolation: i == 0 && firstKeyCubic != null
          ? RivInterpolationType.cubic
          : RivInterpolationType.linear,
      value: value,
      rawObjectIndex: 100 + i,
    );
    if (i == 0) keyframe.cubic = firstKeyCubic;
    property.keyframes.add(keyframe);
  }
  keyed.properties.add(property);
  animation.keyedObjects.add(keyed);
  return animation;
}

void main() {
  Future<RivAnimationModel> pump(
    WidgetTester tester, {
    required List<(int, double)> keys,
    RivCubicEase? firstKeyCubic,
    void Function(RivKeyFrameModel, int)? onRetime,
    void Function(RivKeyFrameModel, double)? onSetValue,
    void Function(RivKeyFrameModel, RivCubicEase)? onSetCubic,
  }) async {
    final animation = _animation(keys: keys, firstKeyCubic: firstKeyCubic);
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
              onSetCubicEase: onSetCubic,
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
  testWidgets('dragging a tangent handle reports a new ease', (tester) async {
    final eases = <RivCubicEase>[];
    await pump(
      tester,
      keys: [(0, 0), (60, 100)],
      firstKeyCubic: RivCubicEase.easeInOut,
      onRetime: (_, _) {},
      onSetValue: (_, _) {},
      onSetCubic: (_, ease) => eases.add(ease),
    );

    final surface = tester.getRect(find.byType(CustomPaint).last);
    // Outgoing handle sits at segment fraction (x1=0.42, y1=0). The
    // padded value range is [-10, 110]; value 0 maps near the bottom
    // and value 100 near the top.
    const pad = 14.0;
    final usable = surface.height - 2 * pad;
    double yFor(double value) =>
        surface.bottom - pad - ((value + 10) / 120) * usable;
    final p0 = Offset(surface.left, yFor(0));
    final p1 = Offset(surface.right, yFor(100));
    final outgoing = Offset(
      p0.dx + (p1.dx - p0.dx) * 0.42,
      p0.dy + (p1.dy - p0.dy) * 0.0,
    );

    final gesture = await tester.startGesture(outgoing);
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(eases, isNotEmpty);
    // Handle moved left: x1 must shrink; y1/x2/y2 unchanged.
    expect(eases.last.x1, lessThan(0.42));
    expect(eases.last.y1, closeTo(0, 0.05));
    expect(eases.last.x2, closeTo(0.58, 1e-6));
    expect(eases.last.y2, closeTo(1, 1e-6));
  });

  testWidgets('handles hidden without an ease callback', (tester) async {
    // Should not crash and points still drag normally.
    final values = <double>[];
    await pump(
      tester,
      keys: [(0, 0), (60, 100)],
      firstKeyCubic: RivCubicEase.easeInOut,
      onRetime: (_, _) {},
      onSetValue: (_, value) => values.add(value),
    );
    expect(find.byType(CurveEditor), findsOneWidget);
  });
  testWidgets('sibling channels overlay and expand the value range', (
    tester,
  ) async {
    final animation = _multiChannelAnimation();
    final xProperty = animation.keyedObjects.single.properties.first;
    final retimes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: EditorTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: CurveEditor(
              property: xProperty,
              animation: animation,
              siblingProperties: animation.keyedObjects.single.properties,
              onRetimeKeyframe: (_, frame) => retimes.add(frame),
              onSetKeyframeValue: (_, _) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CurveEditor), findsOneWidget);

    // The combined range is [0, 900] padded: X's frame-0 point (value 0)
    // now sits low in the view rather than at the padded bottom of its
    // own [0,100] range. Drag it and confirm the correct point moved.
    final surface = tester.getRect(find.byType(CustomPaint).last);
    const pad = 14.0;
    final usable = surface.height - 2 * pad;
    // Combined padded range: [-90, 990]. Value 0 -> t = 90/1080.
    final y = surface.bottom - pad - (90 / 1080) * usable;
    final gesture = await tester.startGesture(Offset(surface.left + 1, y));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      retimes,
      isNotEmpty,
      reason: 'active-channel points stay draggable with overlays on',
    );
  });

  testWidgets('channel colours are stable per property key', (tester) async {
    expect(CurveEditor.colorFor(13), CurveEditor.colorFor(13));
    expect(CurveEditor.colorFor(13) == CurveEditor.colorFor(14), isFalse);
  });
  testWidgets('box-select then drag moves the whole group', (tester) async {
    final batches = <List<(RivKeyFrameModel, int, double)>>[];
    await pump(
      tester,
      keys: [(10, 20), (30, 50), (50, 80)],
      onRetime: (_, _) {},
      onSetValue: (_, _) {},
    );
    // Re-pump with the transform callback (pump helper lacks it).
    final animation = _animation(keys: [(10, 20), (30, 50), (50, 80)]);
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
              onRetimeKeyframe: (_, _) {},
              onSetKeyframeValue: (_, _) {},
              onTransformKeyframes: batches.add,
            ),
          ),
        ),
      ),
    );

    final surface = tester.getRect(find.byType(CustomPaint).last);
    // Marquee over the middle of the view to catch all three points.
    final marquee = await tester.startGesture(
      Offset(surface.left + 5, surface.top + 5),
    );
    await marquee.moveTo(Offset(surface.right - 5, surface.bottom - 5));
    await tester.pump();
    await marquee.up();
    await tester.pump();

    // Drag the middle point (frame 30 of 60 -> horizontal centre).
    const pad = 14.0;
    final usable = surface.height - 2 * pad;
    // Padded range [14, 86]: value 50 -> t = 36/72 = 0.5.
    final y = surface.bottom - pad - 0.5 * usable;
    final drag = await tester.startGesture(
      Offset(surface.left + surface.width * 0.5, y),
    );
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(batches, isNotEmpty, reason: 'group drag must fire');
    expect(batches.last, hasLength(3), reason: 'all selected points move');
    // 50px of 600px over 60 frames = 5 frames; all move together.
    final frames = [for (final (_, frame, _) in batches.last) frame];
    expect(frames, [15, 35, 55]);
  });
  testWidgets('Alt+drag scales the selected group around its first frame', (
    tester,
  ) async {
    final batches = <List<(RivKeyFrameModel, int, double)>>[];
    final animation = _animation(keys: [(10, 20), (20, 50), (30, 80)]);
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
              onRetimeKeyframe: (_, _) {},
              onSetKeyframeValue: (_, _) {},
              onTransformKeyframes: batches.add,
            ),
          ),
        ),
      ),
    );

    final surface = tester.getRect(find.byType(CustomPaint).last);
    // Select all three points with a marquee.
    final marquee = await tester.startGesture(
      Offset(surface.left + 2, surface.top + 2),
    );
    await marquee.moveTo(Offset(surface.right - 2, surface.bottom - 2));
    await tester.pump();
    await marquee.up();
    await tester.pump();

    // Alt+drag the middle point (frame 20 of 60 -> x at 1/3 width).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    const pad = 14.0;
    final usable = surface.height - 2 * pad;
    // Padded range [14, 86]: value 50 -> t = 0.5.
    final y = surface.bottom - pad - 0.5 * usable;
    final drag = await tester.startGesture(
      Offset(surface.left + surface.width * (20 / 60), y),
    );
    // Span is 20 frames = 200px at 600px/60f; +100px doubles the span.
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(batches, isNotEmpty);
    final frames = [for (final (_, frame, _) in batches.last) frame]..sort();
    // Factor 2 around frame 10: 10 -> 10, 20 -> 30, 30 -> 50.
    expect(frames.first, 10, reason: 'anchor frame must not move');
    expect(frames[1], 30);
    expect(frames[2], 50);
  });
}
