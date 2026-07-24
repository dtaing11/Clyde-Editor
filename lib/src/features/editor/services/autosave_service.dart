import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Periodically writes recovery snapshots of the working document.
///
/// Autosaves go to a sidecar directory (`~/.clyde_editor/autosave/`),
/// never to the user's file, so an app crash can't corrupt originals.
class AutosaveService {
  AutosaveService({
    this.interval = const Duration(seconds: 30),
    Directory? directory,
  }) : _directory =
           directory ??
           Directory(
             '${Platform.environment['HOME'] ?? '.'}/.clyde_editor/autosave',
           );

  final Duration interval;
  final Directory _directory;
  Timer? _timer;
  Uint8List? Function()? _snapshotProvider;
  String _documentName = 'untitled';
  DateTime? _lastSaveTime;

  DateTime? get lastSaveTime => _lastSaveTime;

  /// Latest autosave path for the current document, if one exists.
  File get _autosaveFile =>
      File('${_directory.path}/$_documentName.autosave.riv');

  /// Starts autosaving. [snapshotProvider] returns the current document
  /// bytes, or `null` when there is nothing to save.
  void start({
    required String documentName,
    required Uint8List? Function() snapshotProvider,
  }) {
    stop();
    _documentName = _sanitize(documentName);
    _snapshotProvider = snapshotProvider;
    _timer = Timer.periodic(interval, (_) => saveNow());
  }

  /// Writes a snapshot immediately (also called by the timer).
  Future<bool> saveNow() async {
    final bytes = _snapshotProvider?.call();
    if (bytes == null) return false;
    try {
      await _directory.create(recursive: true);
      await _autosaveFile.writeAsBytes(bytes, flush: true);
      _lastSaveTime = DateTime.now();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Removes the autosave for the current document (call after a real
  /// save, when recovery is no longer needed).
  Future<void> discard() async {
    try {
      if (await _autosaveFile.exists()) await _autosaveFile.delete();
    } on FileSystemException {
      // Best effort.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
}
