import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../riv/riv_document_model.dart';
import '../painting/timeline_animation_painter.dart';
import 'editor_document.dart';

/// Central mutable state of the editor, exposed as a [ChangeNotifier].
///
/// Widgets listen to this controller instead of talking to the engine
/// directly, keeping UI and engine concerns separate (MVC-ish).
class EditorState extends ChangeNotifier {
  EditorState() {
    painter = TimelineAnimationPainter(onTimeChanged: _onPainterTime);
  }

  /// Painter shared by the viewport; drives playback.
  late final TimelineAnimationPainter painter;

  EditorDocument? _document;
  rive.Artboard? _activeArtboard;
  List<rive.Animation> _animations = const [];
  int _selectedAnimationIndex = -1;
  bool _isPlaying = false;
  double _currentTime = 0;
  RivKeyedObjectModel? _selectedKeyedObject;
  final List<Uint8List> _undoStack = [];

  /// Maximum number of undo snapshots retained.
  static const int maxUndoDepth = 50;

  EditorDocument? get document => _document;
  rive.Artboard? get activeArtboard => _activeArtboard;
  List<rive.Animation> get animations => _animations;
  int get selectedAnimationIndex => _selectedAnimationIndex;
  rive.Animation? get selectedAnimation =>
      _selectedAnimationIndex >= 0 &&
          _selectedAnimationIndex < _animations.length
      ? _animations[_selectedAnimationIndex]
      : null;
  bool get isPlaying => _isPlaying;
  double get currentTime => _currentTime;
  double get duration => painter.duration;
  bool get hasDocument => _document != null;

  /// Parsed keyframe tracks for the selected animation, or `null` when
  /// unavailable (no selection, or the file could not be parsed).
  RivAnimationModel? get selectedAnimationModel {
    final artboard = _activeArtboard;
    final animation = selectedAnimation;
    if (artboard == null || animation == null) return null;
    return _document?.animationModel(artboard.name, animation.name);
  }

  /// The keyed object currently inspected, or `null` for none.
  ///
  /// Cleared automatically when the animation or artboard changes.
  RivKeyedObjectModel? get selectedKeyedObject => _selectedKeyedObject;

  /// Selects [keyedObject] for the inspector; pass `null` to clear.
  void selectKeyedObject(RivKeyedObjectModel? keyedObject) {
    if (identical(_selectedKeyedObject, keyedObject)) return;
    _selectedKeyedObject = keyedObject;
    notifyListeners();
  }

  /// Whether the current document supports byte-level editing.
  bool get canEdit => _document?.editor != null;

  /// Whether an undo snapshot is available.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Moves [keyframe] to [newFrame] and reloads the engine so playback
  /// reflects the change. Returns `true` on success.
  Future<bool> retimeKeyframe(RivKeyFrameModel keyframe, int newFrame) async {
    final doc = _document;
    final editor = doc?.editor;
    final animation = selectedAnimationModel;
    if (doc == null || editor == null || animation == null) return false;

    final before = editor.bytes();
    final changed = editor.retimeKeyframe(
      keyframe,
      newFrame,
      durationFrames: animation.durationFrames,
    );
    if (!changed) return false;

    _pushUndo(before);
    return _reloadEngine(doc.name, editor.bytes());
  }

  /// Reverts the most recent edit.
  Future<bool> undo() async {
    final doc = _document;
    if (doc == null || _undoStack.isEmpty) return false;
    final bytes = _undoStack.removeLast();
    return _reloadEngine(doc.name, bytes);
  }

  void _pushUndo(Uint8List bytes) {
    _undoStack.add(bytes);
    if (_undoStack.length > maxUndoDepth) _undoStack.removeAt(0);
  }

  /// Re-decodes [bytes] in the engine, preserving artboard/animation
  /// selection, playhead time and the inspected object where possible.
  Future<bool> _reloadEngine(String name, Uint8List bytes) async {
    final previousArtboardName = _activeArtboard?.name;
    final previousAnimationIndex = _selectedAnimationIndex;
    final previousKeyedObjectId = _selectedKeyedObject?.objectId;
    final previousTime = _currentTime;
    final wasPlaying = _isPlaying;

    final doc = await EditorDocument.decode(name, bytes);
    if (doc == null) return false;

    _document?.dispose();
    _document = doc;

    final artboard =
        doc.artboards
            .where((a) => a.name == previousArtboardName)
            .firstOrNull ??
        doc.artboards.first;
    selectArtboard(artboard);

    if (previousAnimationIndex >= 0 &&
        previousAnimationIndex < _animations.length) {
      selectAnimation(previousAnimationIndex);
    }
    if (previousKeyedObjectId != null) {
      _selectedKeyedObject = selectedAnimationModel?.keyedObjects
          .where((o) => o.objectId == previousKeyedObjectId)
          .firstOrNull;
    }
    seek(previousTime);
    if (wasPlaying) togglePlay();
    notifyListeners();
    return true;
  }

  /// Loads a document from a Flutter asset bundle path.
  Future<bool> loadFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final name = assetPath.split('/').last.replaceAll('.riv', '');
    return _openDocument(name, data.buffer.asUint8List());
  }

  /// Loads a document from raw bytes (e.g. a file picked from disk).
  Future<bool> loadFromBytes(String name, Uint8List bytes) {
    return _openDocument(name, bytes);
  }

  Future<bool> _openDocument(String name, Uint8List bytes) async {
    final doc = await EditorDocument.decode(name, bytes);
    if (doc == null) return false;

    _document?.dispose();
    _document = doc;
    _undoStack.clear();
    selectArtboard(doc.artboards.first);
    return true;
  }

  /// Makes [artboard] the one shown in the viewport.
  void selectArtboard(rive.Artboard artboard) {
    _activeArtboard = artboard;
    _animations = _document?.animationsOf(artboard) ?? const [];
    _selectedAnimationIndex = _animations.isEmpty ? -1 : 0;
    _isPlaying = false;
    _currentTime = 0;
    _selectedKeyedObject = null;
    painter.artboardChanged(artboard);
    painter.setAnimation(selectedAnimation);
    notifyListeners();
  }

  /// Selects the animation at [index] on the active artboard.
  void selectAnimation(int index) {
    if (index < 0 || index >= _animations.length) return;
    _selectedAnimationIndex = index;
    _isPlaying = false;
    _currentTime = 0;
    _selectedKeyedObject = null;
    painter.setAnimation(selectedAnimation);
    notifyListeners();
  }

  void togglePlay() {
    if (selectedAnimation == null) return;
    _isPlaying = !_isPlaying;
    _isPlaying ? painter.play() : painter.pause();
    notifyListeners();
  }

  /// Scrubs the timeline to [seconds].
  void seek(double seconds) {
    painter.seek(seconds);
    _currentTime = painter.time;
    notifyListeners();
  }

  void _onPainterTime(double time) {
    _currentTime = time;
    if (!painter.isPlaying && _isPlaying) {
      // Non-looping animation reached its end.
      _isPlaying = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _document?.dispose();
    painter.dispose();
    super.dispose();
  }
}
