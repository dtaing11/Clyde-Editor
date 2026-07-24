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
