import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'package:rive_editor/src/app.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/animation_commands.dart';
import 'package:rive_editor/src/core/commands/shape_commands.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_format.dart';
import 'package:rive_editor/src/riv/riv_hierarchy.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';
import 'package:rive_editor/src/features/editor/widgets/animations_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/canvas_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/scene_hierarchy_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/timeline_panel.dart';

/// End-to-end check on the real macOS runner: the editor boots, the native
/// Rive engine initializes, a blank document is created, and all panels
/// plus a rendered artboard are present.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor shell starts with a blank document and renders it', (
    tester,
  ) async {
    await rive.RiveNative.init();
    await tester.pumpWidget(const RiveEditorApp());

    // Allow async .riv decode to finish.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(rive.RiveArtboardWidget).evaluate().isNotEmpty) break;
    }

    // Editor chrome is present.
    expect(find.byType(SceneHierarchyPanel), findsOneWidget);
    expect(find.byType(AnimationsPanel), findsOneWidget);
    expect(find.byType(CanvasPanel), findsOneWidget);
    expect(find.byType(TimelinePanel), findsOneWidget);

    // Blank startup document decoded and rendered by the Rive engine.
    expect(find.byType(rive.RiveArtboardWidget), findsOneWidget);
    expect(find.text('untitled.riv'), findsOneWidget);

    // A blank document has no animations yet, so the timeline shows
    // its empty state instead of transport controls.
    expect(find.text('Select an animation'), findsOneWidget);
  });

  testWidgets('draw, select, and drag a shape on the real canvas', (
    tester,
  ) async {
    await rive.RiveNative.init();
    await tester.pumpWidget(const RiveEditorApp());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(rive.RiveArtboardWidget).evaluate().isNotEmpty) break;
    }

    // Activate the Rectangle tool via its tool strip button.
    await tester.tap(find.byTooltip('Rectangle (R)'));
    await tester.pump();

    // Draw: drag over the canvas centre.
    final canvas = find.byType(CanvasPanel);
    final canvasCentre = tester.getCenter(canvas);
    final drawGesture = await tester.startGesture(
      canvasCentre - const Offset(60, 60),
    );
    await drawGesture.moveTo(canvasCentre + const Offset(60, 60));
    await drawGesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The document now contains one Shape and the hierarchy shows it.
    expect(find.text('Rectangle 1'), findsOneWidget);

    // Select with the Selection tool by clicking the shape centre.
    await tester.tap(find.byTooltip('Select (V)'));
    await tester.pump();
    await tester.tapAt(canvasCentre);
    await tester.pump();

    final canvasWidget = tester.widget<CanvasPanel>(
      find.byType(CanvasPanel).first,
    );
    final editorState = canvasWidget.state;
    expect(
      editorState.selection.selected,
      isNotEmpty,
      reason: 'clicking a drawn shape must select it',
    );

    double shapeX() {
      final raw = editorState.document!.editor!.raw;
      final objects = RivHierarchy.componentObjects(raw, 0);
      for (final object in objects.values) {
        if (object.typeKey == RivTypeKeys.shape) {
          return object.property(RivPropertyKeys.nodeX)!.floatValue;
        }
      }
      fail('shape not found');
    }

    final xBefore = shapeX();

    // Drag the selected shape 80px right.
    final moveGesture = await tester.startGesture(canvasCentre);
    await moveGesture.moveTo(canvasCentre + const Offset(40, 0));
    await moveGesture.moveTo(canvasCentre + const Offset(80, 0));
    await moveGesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      shapeX(),
      greaterThan(xBefore),
      reason: 'dragging a selected shape must move it',
    );
  });

  testWidgets('shape command output decodes in the native engine', (
    tester,
  ) async {
    await rive.RiveNative.init();

    // Build a blank document, add a rectangle via the command, and
    // prove the shipping engine accepts and renders the result.
    final bytes = RivDocumentBuilder.newDocument();
    final editor = RivDocumentEditor.parse(bytes);
    final context = _EngineTestContext(editor);
    final command = AddShapeCommand(
      artboardOrdinal: 0,
      kind: RivShapeKind.rectangle,
      name: 'EngineRect',
      x: 250,
      y: 250,
      width: 100,
      height: 80,
    );
    expect(command.execute(context).succeeded, isTrue);

    final file = await rive.File.decode(
      editor.bytes(),
      riveFactory: rive.Factory.rive,
    );
    expect(file, isNotNull, reason: 'engine must accept edited bytes');
    final artboard = file!.artboardAt(0);
    expect(artboard, isNotNull);
    final component = artboard!.component('EngineRect');
    expect(component, isNotNull, reason: 'shape must exist in the engine');
    artboard.dispose();
    file.dispose();
  });

  testWidgets('animation + keyframe commands decode and play in the engine', (
    tester,
  ) async {
    await rive.RiveNative.init();

    final editor = RivDocumentEditor.parse(RivDocumentBuilder.newDocument());
    final context = _EngineTestContext(editor);
    expect(
      AddShapeCommand(
        artboardOrdinal: 0,
        kind: RivShapeKind.rectangle,
        name: 'Mover',
        x: 100,
        y: 100,
        width: 50,
        height: 50,
      ).execute(context).succeeded,
      isTrue,
    );
    expect(
      AddAnimationCommand(
        artboardOrdinal: 0,
        name: 'Slide',
      ).execute(context).succeeded,
      isTrue,
    );
    // Key nodeX (13) of the Shape (component 1) at frames 0 and 60.
    for (final (frame, value) in [(0, 100.0), (60, 300.0)]) {
      expect(
        InsertKeyframeCommand(
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13,
          frame: frame,
          value: value,
        ).execute(context).succeeded,
        isTrue,
      );
    }

    final file = await rive.File.decode(
      editor.bytes(),
      riveFactory: rive.Factory.rive,
    );
    expect(file, isNotNull, reason: 'engine must accept animated bytes');
    final artboard = file!.artboardAt(0, frameOrigin: false);
    final animation = artboard!.animationNamed('Slide');
    expect(animation, isNotNull, reason: 'animation must exist in the engine');

    // The engine must evaluate the keyframes: x is 100 at t=0 and 200
    // at t=0.5s (frame 30, halfway between (0,100) and (60,300)).
    final component = artboard.component('Mover')!;
    animation!.time = 0;
    animation.apply();
    artboard.advance(0);
    expect(component.x, closeTo(100, 0.5));

    animation.time = 0.5;
    animation.apply();
    artboard.advance(0);
    expect(component.x, closeTo(200, 0.5));

    animation.dispose();
    artboard.dispose();
    file.dispose();
  });

  testWidgets('text command output decodes in the native engine', (
    tester,
  ) async {
    await rive.RiveNative.init();

    final fontData = await rootBundle.load('assets/fonts/Inter.ttf');
    final editor = RivDocumentEditor.parse(RivDocumentBuilder.newDocument());
    final context = _EngineTestContext(editor);
    final command = AddTextCommand(
      artboardOrdinal: 0,
      name: 'EngineText',
      text: 'Hello Clyde',
      x: 250,
      y: 250,
      fontBytes: fontData.buffer.asUint8List(),
      fontName: 'Inter',
    );
    expect(command.execute(context).succeeded, isTrue);

    final file = await rive.File.decode(
      editor.bytes(),
      riveFactory: rive.Factory.rive,
    );
    expect(file, isNotNull, reason: 'engine must accept text bytes');
    final artboard = file!.artboardAt(0);
    expect(artboard!.component('EngineText'), isNotNull);
    artboard.dispose();
    file.dispose();
  });
}

final class _EngineTestContext implements DocumentContext {
  _EngineTestContext(this.editor);

  @override
  final RivDocumentEditor editor;

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {}
}
