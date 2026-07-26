import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';
import 'package:rive_editor/src/shared/widgets/color_picker.dart';

void main() {
  group('hex color helpers', () {
    test('parses RRGGBB as opaque', () {
      expect(parseHexColor('FF8800'), 0xFFFF8800);
      expect(parseHexColor('#ff8800'), 0xFFFF8800);
    });

    test('parses AARRGGBB with alpha', () {
      expect(parseHexColor('80FF8800'), 0x80FF8800);
    });

    test('rejects malformed input', () {
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('12345'), isNull);
      expect(parseHexColor('GGGGGG'), isNull);
      expect(parseHexColor('#12'), isNull);
    });

    test('formats opaque colors without alpha digits', () {
      expect(formatHexColor(0xFFFF8800), 'FF8800');
      expect(formatHexColor(0x80FF8800), '80FF8800');
    });

    test('parse/format round-trips', () {
      for (final color in [0xFF000000, 0xFFFFFFFF, 0x8012AB34]) {
        expect(parseHexColor(formatHexColor(color)), color);
      }
    });
  });

  group('ColorField', () {
    Future<void> pump(
      WidgetTester tester, {
      required int color,
      required ValueChanged<int> onChanged,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: EditorTheme.dark(),
          home: Scaffold(
            body: ColorField(label: 'Fill', color: color, onChanged: onChanged),
          ),
        ),
      );
    }

    testWidgets('shows the current color as hex', (tester) async {
      await pump(tester, color: 0xFF123456, onChanged: (_) {});
      expect(find.text('123456'), findsOneWidget);
    });

    testWidgets('submitting a hex value reports the parsed ARGB', (
      tester,
    ) async {
      int? received;
      await pump(tester, color: 0xFF000000, onChanged: (c) => received = c);

      await tester.enterText(find.byType(TextField), 'FF8800');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(received, 0xFFFF8800);
    });

    testWidgets('invalid hex reverts to the current color', (tester) async {
      int? received;
      await pump(tester, color: 0xFF123456, onChanged: (c) => received = c);

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(received, isNull);
      expect(find.text('123456'), findsOneWidget);
    });

    testWidgets('tapping the swatch opens the picker dialog', (tester) async {
      await pump(tester, color: 0xFF123456, onChanged: (_) {});
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();
      expect(find.byType(EditorColorPicker), findsOneWidget);
    });
  });

  group('EditorColorPicker', () {
    testWidgets('hex entry reports through onChanged', (tester) async {
      int? received;
      await tester.pumpWidget(
        MaterialApp(
          theme: EditorTheme.dark(),
          home: Scaffold(
            body: EditorColorPicker(
              initialColor: 0xFF000000,
              onChanged: (c) => received = c,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '00FF00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(received, 0xFF00FF00);
    });
  });
}
