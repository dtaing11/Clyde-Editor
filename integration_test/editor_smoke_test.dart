import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'package:rive_editor/src/app.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/shape_commands.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';
import 'package:rive_editor/src/features/editor/widgets/animations_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/canvas_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/scene_hierarchy_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/timeline_panel.dart';

/// End-to-end check on the real macOS runner: the editor boots, the native
/// Rive engine initializes, the demo document loads, and all panels plus a
/// rendered artboard are present.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor shell loads demo document and renders artboard', (
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

    // Demo document decoded and artboard is rendered by the Rive engine.
    expect(find.byType(rive.RiveArtboardWidget), findsOneWidget);
    expect(find.text('little_machine.riv'), findsOneWidget);

    // Playback transport is wired up.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.pause), findsOneWidget);
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
