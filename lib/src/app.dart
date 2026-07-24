import 'package:flutter/material.dart';

import 'core/theme/editor_theme.dart';
import 'features/editor/editor_screen.dart';

/// Root widget of the Rive animation editor application.
class RiveEditorApp extends StatelessWidget {
  const RiveEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rive Animation Editor',
      debugShowCheckedModeBanner: false,
      theme: EditorTheme.dark(),
      home: const EditorScreen(),
    );
  }
}
