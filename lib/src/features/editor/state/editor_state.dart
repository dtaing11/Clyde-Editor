import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../core/commands/animation_commands.dart';
import '../../../core/commands/command_processor.dart';
import '../../../core/commands/document_commands.dart';
import '../../../core/commands/editor_command.dart';
import '../../../core/services/selection_service.dart';
import '../../../riv/riv_artboard_editor.dart';
import '../../../riv/riv_document_builder.dart';
import '../../../riv/riv_document_editor.dart';
import '../../../riv/riv_document_model.dart';
import '../../../riv/riv_format.dart';
import '../../../riv/riv_hierarchy.dart';
import '../painting/timeline_animation_painter.dart';
import '../services/autosave_service.dart';
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
/// directly. Every document mutation is dispatched as an
/// [EditorCommand] through the [CommandProcessor]; this class provides
/// the [DocumentContext] the commands run against.
class EditorState extends ChangeNotifier implements DocumentContext {
  EditorState({AutosaveService? autosave})
    : _autosave = autosave ?? AutosaveService() {
    painter = TimelineAnimationPainter(onTimeChanged: _onPainterTime);
    commands = CommandProcessor(context: this);
  }

  /// Painter shared by the viewport; drives playback.
  late final TimelineAnimationPainter painter;

  /// Executes and records every document mutation (§4.4).
  late final CommandProcessor commands;

  final AutosaveService _autosave;

  /// Scene hierarchy UI state (expansion, locks, search).
  final SceneHierarchyController scene = SceneHierarchyController();

  /// The one selection shared by hierarchy, canvas, and inspector
  /// (§2.2 acceptance).
  final SelectionService selection = SelectionService();

  EditorDocument? _document;
  rive.Artboard? _activeArtboard;
  List<rive.Animation> _animations = const [];
  int _selectedAnimationIndex = -1;
  bool _isPlaying = false;
  double _currentTime = 0;
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

  /// Ordinal of the active artboard in the document, or -1.
  int get activeArtboardOrdinal {
    final doc = _document;
    final artboard = _activeArtboard;
    if (doc == null || artboard == null) return -1;
    return doc.artboards.indexOf(artboard);
  }

  /// The keyed object matching the primary selection in the current
  /// animation, or `null` when the selection is not animated here.
  ///
  /// Derived from the shared [selection] service; the timeline and the
  /// scene tree both select through it, so the inspector follows both.
  RivKeyedObjectModel? get selectedKeyedObject {
    final primary = selection.primary;
    if (primary == null || primary.artboardOrdinal != activeArtboardOrdinal) {
      return null;
    }
    return selectedAnimationModel?.keyedObjects
        .where((o) => o.objectId == primary.componentIndex)
        .firstOrNull;
  }

  /// Selects the component behind [keyedObject] in the shared selection.
  void selectKeyedObject(RivKeyedObjectModel? keyedObject) {
    if (keyedObject == null) {
      selection.clear();
      return;
    }
    selection.select([
      SceneNodeRef(activeArtboardOrdinal, keyedObject.objectId),
    ]);
  }

  /// Whether the current document supports byte-level editing.
  bool get canEdit => _document?.editor != null;

  bool get canUndo => commands.canUndo;
  bool get canRedo => commands.canRedo;

  // -- DocumentContext -----------------------------------------------------

  @override
  RivDocumentEditor? get editor => _document?.editor;

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {
    scene.applyRemap(artboardOrdinal, remap);
    selection.applyComponentRemap(artboardOrdinal, remap);
  }

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

  /// Monotonic counter bumped on every document change (open, edit,
  /// undo/redo). Lets consumers cache document-derived structures (hit
  /// testers, trees) and invalidate precisely.
  int get documentEpoch => _documentEpoch;
  int _documentEpoch = 0;

  /// Increments only when a different document is opened, not on
  /// engine reloads after edits. With [activeArtboardOrdinal] this
  /// identifies "the artboard the user is looking at" stably across
  /// edits, so views can refit on navigation but never on edits.
  int get documentSessionId => _documentSessionId;
  int _documentSessionId = 0;

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

  /// Monotonic counter bumped synchronously on every successful raw
  /// document mutation (dispatch/undo/redo), *before* the async engine
  /// reload. Caches that must reflect the raw bytes immediately (hit
  /// testing, overlays) key on this instead of [documentEpoch].
  int get documentRevision => _documentRevision;
  int _documentRevision = 0;

  /// Dispatches [command] through the processor; on success the engine
  /// is reloaded so playback reflects the new document.
  Future<bool> dispatch(EditorCommand command) async {
    final doc = _document;
    if (doc == null) return false;
    if (!commands.execute(command).succeeded) return false;
    _hasUnsavedChanges = true;
    _documentRevision++;
    return _requestEngineReload();
  }

  bool _engineReloadInFlight = false;
  bool _engineReloadQueued = false;

  /// Serialises engine reloads so rapid dispatches (e.g. dragging a
  /// shape) never run concurrent async decodes that race and clobber
  /// each other. While a reload is in flight, further requests coalesce
  /// into one trailing reload of the latest bytes.
  Future<bool> _requestEngineReload() async {
    if (_engineReloadInFlight) {
      _engineReloadQueued = true;
      return true;
    }
    _engineReloadInFlight = true;
    try {
      var ok = true;
      do {
        _engineReloadQueued = false;
        final doc = _document;
        if (doc == null) return false;
        ok = await _reloadEngine(doc.name, doc.editor!.bytes());
      } while (_engineReloadQueued);
      return ok;
    } finally {
      _engineReloadInFlight = false;
    }
  }

  /// Moves [keyframe] to [newFrame]. Returns `true` on success.
  Future<bool> retimeKeyframe(RivKeyFrameModel keyframe, int newFrame) {
    final animation = selectedAnimationModel;
    if (animation == null) return Future.value(false);
    return dispatch(
      RetimeKeyframeCommand(
        rawObjectIndex: keyframe.rawObjectIndex,
        newFrame: newFrame,
        durationFrames: animation.durationFrames,
      ),
    );
  }

  /// Reverts the most recent command.
  Future<bool> undo() async {
    final doc = _document;
    if (doc == null || !commands.undo().succeeded) return false;
    _hasUnsavedChanges = true;
    _documentRevision++;
    return _requestEngineReload();
  }

  /// Re-applies the most recently undone command.
  Future<bool> redo() async {
    final doc = _document;
    if (doc == null || !commands.redo().succeeded) return false;
    _hasUnsavedChanges = true;
    _documentRevision++;
    return _requestEngineReload();
  }

  /// Creates a blank document with one artboard.
  Future<bool> newDocument({
    String name = 'untitled',
    String artboardName = 'Artboard',
    double width = AddArtboardCommand.defaultSize,
    double height = AddArtboardCommand.defaultSize,
    int? backgroundColor,
  }) async {
    final bytes = RivDocumentBuilder.newDocument(
      artboardName: artboardName,
      width: width,
      height: height,
      backgroundColor: backgroundColor,
    );
    final ok = await _openDocument(name, bytes);
    if (ok) _filePath = null;
    return ok;
  }

  /// Appends a new artboard to the document and selects it.
  Future<bool> addArtboard(
    String name, {
    double width = AddArtboardCommand.defaultSize,
    double height = AddArtboardCommand.defaultSize,
    int? backgroundColor,
  }) async {
    final ok = await dispatch(
      AddArtboardCommand(
        name: name,
        width: width,
        height: height,
        backgroundColor: backgroundColor,
      ),
    );
    if (ok) {
      final added = _document?.artboards
          .where((a) => a.name == name)
          .firstOrNull;
      if (added != null) selectArtboard(added);
    }
    return ok;
  }

  /// Embeds an image asset into the document.
  Future<bool> importImageAsset(String name, Uint8List assetBytes) {
    return dispatch(
      ImportImageAssetCommand(name: name, assetBytes: assetBytes),
    );
  }

  /// Records where the document lives on disk (after open or save-as).
  void setFilePath(String? path) {
    _filePath = path;
    notifyListeners();
  }

  // -- Scene hierarchy operations ------------------------------------------

  /// Renames a component (no index shift, so no remap).
  Future<bool> renameComponent(SceneNodeRef ref, String newName) {
    if (scene.isLocked(ref)) return Future.value(false);
    return dispatch(
      RenameComponentCommand(
        artboardOrdinal: ref.artboardOrdinal,
        componentIndex: ref.componentIndex,
        newName: newName,
      ),
    );
  }

  /// Toggles the runtime Hidden flag on a drawable component.
  Future<bool> setComponentHidden(SceneNodeRef ref, bool hidden) {
    if (scene.isLocked(ref)) return Future.value(false);
    return dispatch(
      SetComponentHiddenCommand(
        artboardOrdinal: ref.artboardOrdinal,
        componentIndex: ref.componentIndex,
        hidden: hidden,
      ),
    );
  }

  /// Whether the component is hidden in the file.
  bool isComponentHidden(SceneNodeRef ref) {
    final raw = _document?.editor?.raw;
    if (raw == null) return false;
    return RivArtboardEditor(
      raw,
      ref.artboardOrdinal,
    ).isHidden(ref.componentIndex);
  }

  /// Moves a component under a new parent (drag and drop reorder).
  Future<bool> reparentComponent(
    SceneNodeRef ref,
    int newParentIndex, {
    int? insertAfterSibling,
  }) {
    if (scene.isLocked(ref)) return Future.value(false);
    return dispatch(
      ReparentComponentCommand(
        artboardOrdinal: ref.artboardOrdinal,
        componentIndex: ref.componentIndex,
        newParentIndex: newParentIndex,
        insertAfterSibling: insertAfterSibling,
      ),
    );
  }

  /// Duplicates a component subtree.
  Future<bool> duplicateComponent(SceneNodeRef ref) {
    if (scene.isLocked(ref)) return Future.value(false);
    return dispatch(
      DuplicateComponentCommand(
        artboardOrdinal: ref.artboardOrdinal,
        componentIndex: ref.componentIndex,
      ),
    );
  }

  /// Deletes a component subtree.
  Future<bool> deleteComponent(SceneNodeRef ref) {
    if (scene.isLocked(ref)) return Future.value(false);
    return dispatch(
      DeleteComponentCommand(
        artboardOrdinal: ref.artboardOrdinal,
        componentIndex: ref.componentIndex,
      ),
    );
  }

  /// Re-decodes [bytes] in the engine, preserving artboard/animation
  /// selection and playhead time. The shared selection survives on its
  /// own (structural remaps are applied via [reportComponentRemap]).
  Future<bool> _reloadEngine(String name, Uint8List bytes) async {
    final previousArtboardName = _activeArtboard?.name;
    final previousAnimationIndex = _selectedAnimationIndex;
    final previousTime = _currentTime;
    final wasPlaying = _isPlaying;

    // Reuse the live editor: commands mutate it in place, and any
    // mutation dispatched while this decode was in flight must survive.
    // Re-parsing the snapshot bytes here would silently drop it.
    final doc = await EditorDocument.decode(
      name,
      bytes,
      reuseEditor: _document?.editor,
    );
    if (doc == null) return false;

    _document?.dispose();
    _document = doc;
    _documentEpoch++;

    final artboard =
        doc.artboards
            .where((a) => a.name == previousArtboardName)
            .firstOrNull ??
        doc.artboards.first;
    _applyArtboard(artboard);

    if (previousAnimationIndex >= 0 &&
        previousAnimationIndex < _animations.length) {
      _selectedAnimationIndex = previousAnimationIndex;
      painter.setAnimation(selectedAnimation);
      _syncPainterLoopMode();
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
    _documentEpoch++;
    _documentRevision++;
    _documentSessionId++;
    _filePath = null;
    commands.clear();
    _hasUnsavedChanges = false;
    scene.reset();
    selection.clear();
    _autosave.start(documentName: name, snapshotProvider: exportBytes);
    selectArtboard(doc.artboards.first);
    return true;
  }

  /// Makes [artboard] the one shown in the viewport.
  void selectArtboard(rive.Artboard artboard) {
    selection.clear();
    _applyArtboard(artboard);
    notifyListeners();
  }

  /// Applies artboard-derived state without touching selection (used
  /// by engine reloads, where selection is remapped separately).
  void _applyArtboard(rive.Artboard artboard) {
    _activeArtboard = artboard;
    _animations = _document?.animationsOf(artboard) ?? const [];
    _selectedAnimationIndex = _animations.isEmpty ? -1 : 0;
    _isPlaying = false;
    _currentTime = 0;
    painter.artboardChanged(artboard);
    painter.setAnimation(selectedAnimation);
    _syncPainterLoopMode();
  }

  /// Selects the animation at [index] on the active artboard.
  /// Creates a new animation on the active artboard and selects it.
  Future<bool> addAnimation(String name) async {
    final ordinal = activeArtboardOrdinal;
    if (ordinal < 0) return false;
    final countBefore = _animations.length;
    final ok = await dispatch(
      AddAnimationCommand(artboardOrdinal: ordinal, name: name),
    );
    if (ok && _animations.length > countBefore) {
      selectAnimation(_animations.length - 1);
    }
    return ok;
  }

  /// Copied keyframe payload: which component property it animates and
  /// the value to re-key. Paste inserts at the playhead.
  ({int objectId, int propertyKey, double value})? _keyframeClipboard;

  bool get hasKeyframeClipboard => _keyframeClipboard != null;

  /// Copies a keyframe's target + value for later pasting.
  void copyKeyframe({
    required int objectId,
    required int propertyKey,
    required double value,
  }) {
    _keyframeClipboard = (
      objectId: objectId,
      propertyKey: propertyKey,
      value: value,
    );
    notifyListeners();
  }

  /// Pastes the copied keyframe at the current playhead frame.
  Future<bool> pasteKeyframe() {
    final clip = _keyframeClipboard;
    if (clip == null) return Future.value(false);
    return insertKeyframe(
      objectId: clip.objectId,
      propertyKey: clip.propertyKey,
      value: clip.value,
    );
  }

  /// Loop mode of the selected animation (authored value).
  RivLoopMode get loopMode => selectedAnimationModel?.loop ?? RivLoopMode.loop;

  /// Persists a new loop mode for the selected animation and applies it
  /// to live playback.
  Future<bool> setLoopMode(RivLoopMode mode) async {
    final ordinal = activeArtboardOrdinal;
    if (ordinal < 0 || _selectedAnimationIndex < 0) return false;
    final ok = await dispatch(
      SetAnimationUintCommand(
        artboardOrdinal: ordinal,
        animationOrdinal: _selectedAnimationIndex,
        propertyKey: RivPropertyKeys.animationLoop,
        value: mode.value,
        commandLabel: 'Set loop mode',
      ),
    );
    if (ok) painter.loopMode = mode;
    return ok;
  }

  void _syncPainterLoopMode() {
    painter.loopMode = loopMode;
  }

  /// Deletes [keyframe] from the document (context-menu action).
  Future<bool> deleteKeyframe(RivKeyFrameModel keyframe) {
    if (keyframe.rawObjectIndex < 0) return Future.value(false);
    return dispatch(
      DeleteKeyframeCommand(rawObjectIndex: keyframe.rawObjectIndex),
    );
  }

  /// Keyframes the primary selection's X and Y at the playhead (K
  /// shortcut). Creates a default animation first when none exists.
  Future<bool> keyframeSelectionPosition() async {
    final primary = selection.primary;
    if (primary == null || primary.artboardOrdinal != activeArtboardOrdinal) {
      return false;
    }
    if (selectedAnimationModel == null) {
      final created = await addAnimation('Animation ${_animations.length + 1}');
      if (!created) return false;
    }
    final raw = _document?.editor?.raw;
    if (raw == null) return false;
    final object = RivHierarchy.componentObjectAt(
      raw,
      primary.artboardOrdinal,
      primary.componentIndex,
    );
    if (object == null) return false;

    double floatOf(int key) {
      final property = object.property(key);
      return property != null && property.fieldType == RivFieldType.float
          ? property.floatValue
          : 0;
    }

    final x = floatOf(RivPropertyKeys.nodeX);
    final y = floatOf(RivPropertyKeys.nodeY);
    final okX = await insertKeyframe(
      objectId: primary.componentIndex,
      propertyKey: RivPropertyKeys.nodeX,
      value: x,
    );
    final okY = await insertKeyframe(
      objectId: primary.componentIndex,
      propertyKey: RivPropertyKeys.nodeY,
      value: y,
    );
    return okX && okY;
  }

  /// Keyframes [propertyKey] of component [objectId] with [value] at
  /// the current playhead frame of the selected animation.
  Future<bool> insertKeyframe({
    required int objectId,
    required int propertyKey,
    required double value,
  }) {
    final animation = selectedAnimationModel;
    final ordinal = activeArtboardOrdinal;
    if (animation == null || ordinal < 0) return Future.value(false);
    return dispatch(
      InsertKeyframeCommand(
        artboardOrdinal: ordinal,
        animationOrdinal: _selectedAnimationIndex,
        objectId: objectId,
        propertyKey: propertyKey,
        frame: (_currentTime * animation.fps).round(),
        value: value,
      ),
    );
  }

  void selectAnimation(int index) {
    if (index < 0 || index >= _animations.length) return;
    _selectedAnimationIndex = index;
    _isPlaying = false;
    _currentTime = 0;
    painter.setAnimation(selectedAnimation);
    _syncPainterLoopMode();
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
    _notifyAfterFrame();
  }

  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Coalesces notifications that originate inside the paint phase
  /// (the painter advances during paint) to the end of the frame:
  /// notifying mid-paint schedules builds during the frame, which the
  /// framework forbids. The dispose guard covers callbacks landing
  /// after teardown (e.g. test shutdown mid-frame).
  void _notifyAfterFrame() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _autosave.dispose();
    scene.dispose();
    selection.dispose();
    _document?.dispose();
    painter.dispose();
    super.dispose();
  }
}
