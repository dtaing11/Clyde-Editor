import 'dart:typed_data';

import 'package:rive_native/rive_native.dart' as rive;

/// Facade over the Rive engine runtime.
///
/// Owns global engine concerns (initialization, renderer factory choice)
/// so the rest of the app never reaches into `rive_native` global state.
abstract final class RiveEngine {
  /// The renderer backend used across the whole editor.
  ///
  /// [rive.Factory.rive] uses the GPU-accelerated Rive Renderer.
  static rive.Factory get factory => rive.Factory.rive;

  /// Initializes the native runtime. Safe to call multiple times.
  static Future<bool> init() => rive.RiveNative.init();

  /// Decodes raw `.riv` bytes into a Rive [rive.File].
  static Future<rive.File?> decodeFile(Uint8List bytes) {
    return rive.File.decode(bytes, riveFactory: factory);
  }
}
