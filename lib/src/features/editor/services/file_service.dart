import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Result of a file dialog interaction.
enum FileOpResult { success, cancelled, failed }

/// Handles all disk and dialog interaction for documents and assets.
///
/// Keeps `dart:io`/`file_selector` usage out of state and widgets so the
/// rest of the app stays platform-agnostic and testable.
class FileService {
  static const XTypeGroup _rivTypeGroup = XTypeGroup(
    label: 'Rive files',
    extensions: ['riv'],
  );

  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );

  /// Shows an open dialog and reads the chosen `.riv` file.
  Future<({FileOpResult result, String? name, String? path, Uint8List? bytes})>
  openRiveFile() async {
    final file = await openFile(acceptedTypeGroups: const [_rivTypeGroup]);
    if (file == null) {
      return (result: FileOpResult.cancelled, name: null, path: null, bytes: null);
    }
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.replaceAll('.riv', '');
      return (
        result: FileOpResult.success,
        name: name,
        path: file.path,
        bytes: bytes,
      );
    } on Exception {
      return (result: FileOpResult.failed, name: null, path: null, bytes: null);
    }
  }

  /// Shows an open dialog for an image asset to import.
  Future<({FileOpResult result, String? name, Uint8List? bytes})>
  pickImageAsset() async {
    final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
    if (file == null) {
      return (result: FileOpResult.cancelled, name: null, bytes: null);
    }
    try {
      final bytes = await file.readAsBytes();
      return (result: FileOpResult.success, name: file.name, bytes: bytes);
    } on Exception {
      return (result: FileOpResult.failed, name: null, bytes: null);
    }
  }

  /// Writes [bytes] to [path].
  Future<FileOpResult> writeTo(String path, Uint8List bytes) async {
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      return FileOpResult.success;
    } on FileSystemException {
      return FileOpResult.failed;
    }
  }

  /// Shows a save dialog and writes [bytes]; returns the chosen path.
  Future<({FileOpResult result, String? path})> saveAs(
    Uint8List bytes, {
    required String suggestedName,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_rivTypeGroup],
    );
    if (location == null) return (result: FileOpResult.cancelled, path: null);
    final result = await writeTo(location.path, bytes);
    return (result: result, path: location.path);
  }
}
