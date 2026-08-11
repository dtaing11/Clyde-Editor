import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';
import 'package:rive_editor/src/features/editor/widgets/keyframe_track_list.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';

RivAnimationModel _animation() {
  final animation = RivAnimationModel(name: 'A', fps: 60, durationFrames: 60);
  final keyed = RivKeyedObjectModel(objectId: 1, objectName: 'Shape');
  final property = RivKeyedPropertyModel(propertyKey: 13);
  property.keyframes.addAll([
    RivKeyFrameModel(
      frame: 0,
      interpolation: RivInterpolationType.linear,
      value: 10,
      rawObjectIndex: 5,
    ),
    RivKeyFrameModel(
      frame: 30,
      interpolation: RivInterpolationType.linear,
      value: 50,
      rawObjectIndex: 6,
    ),
  ]);
  keyed.properties.add(property);
  animation.keyedObjects.add(keyed);
  return animation;
}

Future<void> _rightClickTrack(
  WidgetTester tester, {
  required double trackFraction,
}) async {
  // The track area is everything right of the label gutter.
  final row = find.byType(CustomPaint).last;
  final rect = tester.getRect(row);
  final position = Offset(
    rect.left + rect.width * trackFraction,
    rect.center.dy,
  );
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    void Function(
      RivKeyedObjectModel keyedObject,
      RivKeyedPropertyModel property,
      RivKeyFrameModel keyframe,
    )?
    onCopy,
    VoidCallback? onPaste,
    bool canPaste = false,
    ValueChanged<RivKeyFrameModel>? onDelete,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: EditorTheme.dark(),
        home: Scaffold(
          body: KeyframeTrackList(
            animation: _animation(),
            labelWidth: 100,
            onCopyKeyframe: onCopy,
            onPasteKeyframe: onPaste,
            canPaste: canPaste,
            onDeleteKeyframe: onDelete,
          ),
        ),
      ),
    );
  }

  testWidgets('right-clicking a diamond offers Copy and Delete', (
    tester,
  ) async {
    RivKeyFrameModel? copied;
    await pump(
      tester,
      onCopy: (_, _, keyframe) => copied = keyframe,
      onDelete: (_) {},
    );

    // Frame 0 diamond sits at the left edge of the track.
    await _rightClickTrack(tester, trackFraction: 0.0);
    expect(find.text('Copy keyframe'), findsOneWidget);
    expect(find.text('Delete keyframe'), findsOneWidget);

    await tester.tap(find.text('Copy keyframe'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect(copied!.frame, 0);
  });

  testWidgets('paste appears only when the clipboard has content', (
    tester,
  ) async {
    var pasted = false;
    await pump(
      tester,
      onCopy: (_, _, _) {},
      onPaste: () => pasted = true,
      canPaste: true,
    );

    // Right-click empty track space: only Paste applies there.
    await _rightClickTrack(tester, trackFraction: 0.8);
    expect(find.text('Paste at playhead'), findsOneWidget);
    expect(find.text('Copy keyframe'), findsNothing);

    await tester.tap(find.text('Paste at playhead'));
    await tester.pumpAndSettle();
    expect(pasted, isTrue);
  });

  testWidgets('empty clipboard shows no Paste entry', (tester) async {
    await pump(tester, onCopy: (_, _, _) {}, onDelete: (_) {});
    await _rightClickTrack(tester, trackFraction: 0.8);
    expect(find.text('Paste at playhead'), findsNothing);
  });
}
