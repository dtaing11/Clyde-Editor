import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/theme/editor_theme.dart';

void main() {
  test('editor theme builds a dark ThemeData', () {
    final theme = EditorTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, EditorTheme.background);
  });
}
