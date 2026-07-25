
import 'package:flutter/services.dart';

import '../../../core/commands/shape_commands.dart';
import '../../../core/tools/editor_tool.dart';

/// Loads the font used for new text objects.
///
/// Abstracts the asset bundle away from the tool so the tool layer
/// stays pure and testable (§4.6: platform access behind interfaces).
abstract interface class FontProvider {
  /// TTF bytes and display name of the default editor font.
  Future<({Uint8List bytes, String name})> defaultFont();
}

/// [FontProvider] backed by the Flutter asset bundle.
final class BundleFontProvider implements FontProvider {
  const BundleFontProvider();

  static const String _assetPath = 'assets/fonts/Inter.ttf';
  static const String _fontName = 'Inter';

  @override
  Future<({Uint8List bytes, String name})> defaultFont() async {
    final data = await rootBundle.load(_assetPath);
    return (bytes: data.buffer.asUint8List(), name: _fontName);
  }
}

/// Requests text content from the user (canvas shows a themed dialog).
typedef TextContentRequest = Future<String?> Function();

/// Click-to-place text tool.
///
/// Clicking the canvas asks for content via [requestContent] (a dialog
/// in the app; injectable in tests) and dispatches an [AddTextCommand]
/// with the font from [fontProvider].
final class TextTool extends EditorTool {
  TextTool({required this.fontProvider, required this.requestContent});

  static const String toolId = 'text';

  final FontProvider fontProvider;
  final TextContentRequest requestContent;

  int _createdCount = 0;
  bool _placing = false;

  @override
  String get id => toolId;

  @override
  String get label => 'Text';

  @override
  LogicalKeyboardKey? get shortcut => LogicalKeyboardKey.keyT;

  @override
  MouseCursor get cursor => SystemMouseCursors.text;

  @override
  void onPointerDown(ToolContext context, ToolPointerEvent event) {
    if (_placing || context.activeArtboardOrdinal < 0) return;
    _placing = true;
    _place(context, event.scenePosition);
  }

  Future<void> _place(ToolContext context, Offset scenePosition) async {
    try {
      final content = await requestContent();
      if (content == null || content.trim().isEmpty) return;
      final font = await fontProvider.defaultFont();
      _createdCount++;
      context.dispatch(
        AddTextCommand(
          artboardOrdinal: context.activeArtboardOrdinal,
          name: 'Text $_createdCount',
          text: content.trim(),
          x: scenePosition.dx,
          y: scenePosition.dy,
          fontBytes: font.bytes,
          fontName: font.name,
        ),
      );
    } finally {
      _placing = false;
    }
  }

  @override
  void deactivate(ToolContext context) {
    _placing = false;
  }
}
