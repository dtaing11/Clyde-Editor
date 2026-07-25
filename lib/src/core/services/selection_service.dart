import 'package:flutter/foundation.dart';

import '../model/scene_node_ref.dart';

/// How a selection gesture combines with the existing selection.
enum SelectionMode {
  /// Replace the selection with the given nodes.
  replace,

  /// Toggle each node (cmd/ctrl-click).
  toggle,

  /// Extend a contiguous range from the anchor (shift-click). The
  /// range itself is computed by the caller, which knows the visual
  /// ordering; the service records the anchor.
  range,
}

/// The single selection shared by hierarchy, canvas, and inspector
/// (§2.2 acceptance: one selection service, not per-panel state).
///
/// Multi-select semantics: [primary] is the most recently selected
/// node (the one the inspector shows in detail); [selected] is the
/// full set. The [anchor] supports shift-range selection.
final class SelectionService extends ChangeNotifier {
  final Set<SceneNodeRef> _selected = {};
  SceneNodeRef? _primary;
  SceneNodeRef? _anchor;

  /// Unmodifiable view of the selected nodes.
  Set<SceneNodeRef> get selected => Set.unmodifiable(_selected);

  /// Most recently selected node, or `null` when nothing is selected.
  SceneNodeRef? get primary => _primary;

  /// Anchor for range selection (last replace/toggle target).
  SceneNodeRef? get anchor => _anchor;

  bool get isEmpty => _selected.isEmpty;
  int get count => _selected.length;

  bool contains(SceneNodeRef ref) => _selected.contains(ref);

  /// Applies a selection gesture on [nodes] using [mode].
  void select(
    Iterable<SceneNodeRef> nodes, {
    SelectionMode mode = SelectionMode.replace,
  }) {
    final targets = nodes.toList();
    switch (mode) {
      case SelectionMode.replace:
        _selected
          ..clear()
          ..addAll(targets);
        _primary = targets.lastOrNull;
        _anchor = targets.lastOrNull;
      case SelectionMode.toggle:
        for (final ref in targets) {
          if (!_selected.remove(ref)) _selected.add(ref);
        }
        _primary = _selected.contains(targets.lastOrNull)
            ? targets.lastOrNull
            : _selected.lastOrNull;
        _anchor = targets.lastOrNull;
      case SelectionMode.range:
        _selected.addAll(targets);
        _primary = targets.lastOrNull;
    }
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty && _primary == null) return;
    _selected.clear();
    _primary = null;
    _anchor = null;
    notifyListeners();
  }

  /// Migrates selection through an index [remap] after a structural
  /// document change (old index -> new index, -1 for removed).
  void applyComponentRemap(int artboardOrdinal, Map<int, int> remap) {
    SceneNodeRef? migrate(SceneNodeRef? ref) {
      if (ref == null || ref.artboardOrdinal != artboardOrdinal) return ref;
      final newIndex = remap[ref.componentIndex] ?? -1;
      return newIndex >= 0 ? SceneNodeRef(artboardOrdinal, newIndex) : null;
    }

    final migrated = <SceneNodeRef>{
      for (final ref in _selected)
        if (migrate(ref) != null) migrate(ref)!,
    };
    _selected
      ..clear()
      ..addAll(migrated);
    _primary = migrate(_primary);
    _anchor = migrate(_anchor);
    notifyListeners();
  }
}
