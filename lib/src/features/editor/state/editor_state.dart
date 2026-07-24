import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../riv/riv_artboard_editor.dart';
import '../../../riv/riv_document_builder.dart';
import '../../../riv/riv_document_model.dart';
import '../../../riv/riv_hierarchy.dart';
import '../painting/timeline_animation_painter.dart';
import '../services/autosave_service.dart';
import '../services/document_history.dart';
import 'editor_document.dart';
import 'scene_hierarchy_controller.dart';

/// How times are displayed across the editor UI.
enum TimeDisplayMode {
  /// Frame numbers (e.g. `15f`), the animator-friendly unit.
  frames,

  /// Seconds with fractions (e.g. `0.25s`).
  seconds,
}

/// Central mutable state of the editor, exposed as a [ChangeNotifier].
///
/// Widgets listen to this controller instead of talking to the engine
/// directly, keeping UI and engine concerns separate (MVC-ish).
class EditorState extends ChangeNotifier {
  EditorState({AutosaveService? autosave})
    : _autosave = autosave ?? AutosaveService() {
    painter = TimelineAnimationPainter(onTimeChanged: _onPainterTime);
  }

  /// Painter shared by the viewport; drives playback.
  late final TimelineAnimationPainter painter;

  final AutosaveService _autosave;
  final DocumentHistory _history = DocumentHistory();

  /// Scene hierarchy UI state (selection, expansion, locks, search).
  final SceneHierarchyController scene = SceneHierarchyController();

  EditorDocument? _document;
  rive.Artboard? _activeArtboard;
  List<rive.Animation> _animations = const [];
  int _selectedAnimationIndex = -1;
  bool _isPlaying = false;
  double _currentTime = 0;
  RivKeyedObjectModel? _selectedKeyedObject;
  String? _filePath;

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

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// Disk path of the current document, `null` for unsaved documents.
  String? get filePath => _filePath;

  /// Component trees for every artboard, for the scene hierarchy panel.
  List<RivHierarchyNode> get hierarchyTrees {
    final raw = _document?.editor?.raw;
    return raw == null ? const [] : RivHierarchy.artboardTrees(raw);
  }

  /// Assets embedded in or referenced by the document.
  List<RivAssetInfo> get assets {
    final raw = _document?.editor?.raw;
    return raw == null ? const [] : RivHierarchy.assets(raw);
  }

  /// Time of the most recent autosave, for status display.
  DateTime? get lastAutosaveTime => _autosave.lastSaveTime;

  /// Whether there are edits that have not been saved.
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool _hasUnsavedChanges = false;

  /// Current bytes of the document including edits, or `null` when the
  /// document is not editable.
  Uint8List? exportBytes() => _document?.editor?.bytes();

  /// Marks the document saved (called after a successful export).
  void markSaved() {
    if (!_hasUnsavedChanges) return;
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  TimeDisplayMode _timeDisplayMode = TimeDisplayMode.frames;

  /// Current unit used to display times in the timeline and inspector.
  TimeDisplayMode get timeDisplayMode => _timeDisplayMode;

  /// Frames per second of the selected animation (falls back to 60).
  int get fps => selectedAnimationModel?.fps ?? 60;

  /// Switches between frame and second display.
  void setTimeDisplayMode(TimeDisplayMode mode) {
    if (_timeDisplayMode == mode) return;
    _timeDisplayMode = mode;
    notifyListeners();
  }

  /// Formats [seconds] according to [timeDisplayMode].
  String formatTime(double seconds) {
    switch (_timeDisplayMode) {
      case TimeDisplayMode.frames:
        return '${(seconds * fps).round()}f';
      case TimeDisplayMode.seconds:
        return '${seconds.toStringAsFixed(2)}s';
    }
  }

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

    _history.push(before);
    _hasUnsavedChanges = true;
    return _reloadEngine(doc.name, editor.bytes());
  }

  /// Reverts the most recent edit.
  Future<bool> undo() async {
    final doc = _document;
    final current = exportBytes();
    if (doc == null || current == null) return false;
    final bytes = _history.undo(current);
    if (bytes == null) return false;
    _hasUnsavedChanges = true;
    return _reloadEngine(doc.name, bytes);
  }

  /// Re-applies the most recently undone edit.
  Future<bool> redo() async {
    final doc = _document;
    final current = exportBytes();
    if (doc == null || current == null) return false;
    final bytes = _history.redo(current);
    if (bytes == null) return false;
    _hasUnsavedChanges = true;
    return _reloadEngine(doc.name, bytes);
  }

  /// Creates a blank document with one artboard.
  Future<bool> newDocument({String name = 'untitled'}) async {
    final bytes = RivDocumentBuilder.newDocument();
    final ok = await _openDocument(name, bytes);
    if (ok) _filePath = null;
    return ok;
  }

  /// Appends a new artboard to the document and selects it.
  Future<bool> addArtboard(String name) async {
    final doc = _document;
    final editor = doc?.editor;
    if (doc == null || editor == null) return false;

    final before = editor.bytes();
    RivDocumentBuilder.appendArtboard(editor.raw, name: name);
    editor.rebuild();
    _history.push(before);
    _hasUnsavedChanges = true;
    final ok = await _reloadEngine(doc.name, editor.bytes());
    if (ok) {
      final added = _document?.artboards
          .where((a) => a.name == name)
          .firstOrNull;
      if (added != null) selectArtboard(added);
    }
    return ok;
  }

  /// Embeds an image asset into the document.
  Future<bool> importImageAsset(String name, Uint8List assetBytes) async {
    final doc = _document;
    final editor = doc?.editor;
    if (doc == null || editor == null) return false;

    final before = editor.bytes();
    RivDocumentBuilder.embedImageAsset(
      editor.raw,
      name: name,
      bytes: assetBytes,
      assetId: RivDocumentBuilder.nextAssetId(editor.raw),
    );
    editor.rebuild();
    _history.push(before);
    _hasUnsavedChanges = true;
    return _reloadEngine(doc.name, editor.bytes());
  }

  /// Records where the document lives on disk (after open or save-as).
  void setFilePath(String? path) {
    _filePath = path;
    notifyListeners();
  }

  // -- Scene hierarchy operations ------------------------------------------

  /// Renames a component. Rename does not shift indices, so no remap.
  Future<bool> renameComponent(SceneNodeRef ref, String newName) {
    return _structuralEdit(ref, requiresRemap: false, (editor) {
      final ok = editor.rename(ref.componentIndex, newName);
      return ok ? const RivStructuralResult.success({}) : null;
    });
  }

  /// Toggles the runtime Hidden flag on a drawable component.
  Future<bool> setComponentHidden(SceneNodeRef ref, bool hidden) {
    return _structuralEdit(ref, requiresRemap: false, (editor) {
      final ok = editor.setHidden(ref.componentIndex, hidden);
      return ok ? const RivStructuralResult.success({}) : null;
    });
  }

  /// Whether the component is hidden in the file.
  bool isComponentHidden(SceneNodeRef ref) {
    final raw = _document?.editor?.raw;
    if (raw == null) return false;
    return RivArtboardEditor(raw, ref.artboardOrdinal)
        .isHidden(ref.componentIndex);
  }

  /// Moves a component under a new parent (drag and drop reorder).
  Future<bool> reparentComponent(
    SceneNodeRef ref,
    int newParentIndex, {
    int? insertAfterSibling,
  }) {
    return _structuralEdit(
      ref,
      (editor) => editor.reparent(
        ref.componentIndex,
        newParentIndex,
        insertAfterSibling: insertAfterSibling,
      ),
    );
  }

  /// Duplicates a component subtree.
  Future<bool> duplicateComponent(SceneNodeRef ref) {
    return _structuralEdit(ref, (editor) => editor.duplicate(ref.componentIndex));
  }

  /// Deletes a component subtree.
  Future<bool> deleteComponent(SceneNodeRef ref) {
    return _structuralEdit(ref, (editor) => editor.delete(ref.componentIndex));
  }

  /// Runs a structural operation transactionally: snapshot for undo,
  /// apply, remap UI state, and reload the engine. Locked components
  /// reject edits at this boundary.
  Future<bool> _structuralEdit(
    SceneNodeRef ref,
    RivStructuralResult? Function(RivArtboardEditor) operation, {
    bool requiresRemap = true,
  }) async {
    final doc = _document;
    final editor = doc?.editor;
    if (doc == null || editor == null) return false;
    if (scene.isLocked(ref)) return false;

    final before = editor.bytes();
    final result = operation(
      RivArtboardEditor(editor.raw, ref.artboardOrdinal),
    );
    if (result == null || !result.succeeded) return false;

    editor.rebuild();
    _history.push(before);
    _hasUnsavedChanges = true;
    if (requiresRemap) {
      scene.applyRemap(ref.artboardOrdinal, result.remap);
    }
    return _reloadEngine(doc.name, editor.bytes());
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
    _filePath = null;
    _history.clear();
    _hasUnsavedChanges = false;
    scene.reset();
    _autosave.start(documentName: name, snapshotProvider: exportBytes);
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
    _autosave.dispose();
    scene.dispose();
    _document?.dispose();
    painter.dispose();
    super.dispose();
  }
}
