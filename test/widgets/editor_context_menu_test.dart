import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';
import 'package:rive_editor/src/shared/widgets/editor_context_menu.dart';

void main() {
  Widget host({required void Function(BuildContext) onOpen}) {
    return MaterialApp(
      theme: EditorTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows entries and returns the tapped value', (tester) async {
    String? result;
    await tester.pumpWidget(
      host(
        onOpen: (context) async {
          result = await showEditorContextMenu<String>(
            context: context,
            globalPosition: const Offset(100, 100),
            entries: const [
              ContextMenuEntry(value: 'a', label: 'Alpha'),
              ContextMenuEntry(
                value: 'b',
                label: 'Beta',
                destructive: true,
                dividerBefore: true,
              ),
            ],
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(result, 'b');
  });

  testWidgets('destructive entries use the warning colour', (tester) async {
    await tester.pumpWidget(
      host(
        onOpen: (context) {
          showEditorContextMenu<String>(
            context: context,
            globalPosition: const Offset(100, 100),
            entries: const [
              ContextMenuEntry(value: 'x', label: 'Delete', destructive: true),
            ],
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Delete'));
    expect(text.style?.color, EditorTheme.playhead);
  });

  testWidgets('dismissing without a choice returns null', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(
      host(
        onOpen: (context) async {
          result = await showEditorContextMenu<String>(
            context: context,
            globalPosition: const Offset(100, 100),
            entries: const [ContextMenuEntry(value: 'a', label: 'Alpha')],
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Tap outside the menu to dismiss.
    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
