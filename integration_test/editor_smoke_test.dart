import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'package:rive_editor/src/app.dart';
import 'package:rive_editor/src/features/editor/widgets/hierarchy_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/timeline_panel.dart';
import 'package:rive_editor/src/features/editor/widgets/viewport_panel.dart';

/// End-to-end check on the real macOS runner: the editor boots, the native
/// Rive engine initializes, the demo document loads, and all three panels
/// plus a rendered artboard are present.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor shell loads demo document and renders artboard',
      (tester) async {
    await rive.RiveNative.init();
    await tester.pumpWidget(const RiveEditorApp());

    // Allow async .riv decode to finish.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(rive.RiveArtboardWidget).evaluate().isNotEmpty) break;
    }

    // Editor chrome is present.
    expect(find.byType(HierarchyPanel), findsOneWidget);
    expect(find.byType(ViewportPanel), findsOneWidget);
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
}
