import 'dart:typed_data';

/// Undo/redo history of document byte snapshots.
///
/// Snapshot-based rather than command-based: `.riv` documents are small
/// and byte snapshots make history trivially correct across any edit
/// type. Bounded by [maxDepth].
class DocumentHistory {
  DocumentHistory({this.maxDepth = 50});

  final int maxDepth;
  final List<Uint8List> _undo = [];
  final List<Uint8List> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;

  /// Records [snapshot] (the state *before* an edit) and clears the redo
  /// branch, as a new edit invalidates it.
  void push(Uint8List snapshot) {
    _undo.add(snapshot);
    _redo.clear();
    if (_undo.length > maxDepth) _undo.removeAt(0);
  }

  /// Returns the previous state, storing [current] for redo.
  Uint8List? undo(Uint8List current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  /// Returns the next state, storing [current] for undo.
  Uint8List? redo(Uint8List current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
