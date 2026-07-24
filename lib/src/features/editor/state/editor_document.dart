import 'dart:typed_data';

import 'package:rive_native/rive_native.dart' as rive;

import '../../../engine/rive_engine.dart';
import '../../../riv/riv_document_editor.dart';
import '../../../riv/riv_document_model.dart';

/// A loaded `.riv` document: engine-side resources plus the editable
/// byte-level representation.
///
/// Owns the underlying native resources. Call [dispose] when the document
/// is closed or replaced.
class EditorDocument {
  EditorDocument._({
    required this.name,
    required this.file,
    required this.artboards,
    required this.editor,
  });

  /// Display name (usually the file name without extension).
  final String name;

  /// The decoded Rive file backing this document.
  final rive.File file;

  /// All artboards contained in [file].
  final List<rive.Artboard> artboards;

  /// Editable byte-level document, `null` when our parser could not read
  /// the file (the engine may still render formats we don't parse yet).
  final RivDocumentEditor? editor;

  /// Editor-side display model (keyed objects, tracks, keyframes).
  RivDocumentModel? get model => editor?.model;

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

    RivDocumentEditor? editor;
    try {
      editor = RivDocumentEditor.parse(bytes);
    } on Exception {
      // Non-fatal: timeline tracks and editing are simply unavailable.
      editor = null;
    }
    return EditorDocument._(
      name: name,
      file: file,
      artboards: artboards,
      editor: editor,
    );
  }

  /// Animations defined on [artboard].
  List<rive.Animation> animationsOf(rive.Artboard artboard) {
    return [
      for (var i = 0; i < artboard.animationCount(); i++)
        artboard.animationAt(i),
    ];
  }

  /// Parsed keyframe model for [artboardName]/[animationName], or `null`.
  RivAnimationModel? animationModel(String artboardName, String animationName) {
    final artboard = model?.artboards
        .where((a) => a.name == artboardName)
        .firstOrNull;
    return artboard?.animations
        .where((a) => a.name == animationName)
        .firstOrNull;
  }

  void dispose() {
    for (final artboard in artboards) {
      artboard.dispose();
    }
    file.dispose();
  }
}
