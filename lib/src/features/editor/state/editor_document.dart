import 'dart:typed_data';

import 'package:rive_native/rive_native.dart' as rive;

import '../../../engine/rive_engine.dart';

/// An immutable handle to a loaded `.riv` document and its artboard contents.
///
/// Owns the underlying native resources. Call [dispose] when the document
/// is closed or replaced.
class EditorDocument {
  EditorDocument._({
    required this.name,
    required this.file,
    required this.artboards,
  });

  /// Display name (usually the file name without extension).
  final String name;

  /// The decoded Rive file backing this document.
  final rive.File file;

  /// All artboards contained in [file].
  final List<rive.Artboard> artboards;

  /// Decodes [bytes] into a document, or returns `null` on failure.
  static Future<EditorDocument?> decode(String name, Uint8List bytes) async {
    final file = await RiveEngine.decodeFile(bytes);
    if (file == null) return null;

    final artboards = <rive.Artboard>[];
    for (var i = 0; ; i++) {
      final artboard = file.artboardAt(i);
      if (artboard == null) break;
      artboards.add(artboard);
    }
    if (artboards.isEmpty) {
      file.dispose();
      return null;
    }
    return EditorDocument._(name: name, file: file, artboards: artboards);
  }

  /// Animations defined on [artboard].
  List<rive.Animation> animationsOf(rive.Artboard artboard) {
    return [
      for (var i = 0; i < artboard.animationCount(); i++) artboard.animationAt(i),
    ];
  }

  void dispose() {
    for (final artboard in artboards) {
      artboard.dispose();
    }
    file.dispose();
  }
}
