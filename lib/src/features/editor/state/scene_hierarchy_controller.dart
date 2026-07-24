import 'package:flutter/foundation.dart';

import '../../../riv/riv_hierarchy.dart';

/// Location of a component: which artboard tree it lives in plus its
/// component index within that artboard.
@immutable
class SceneNodeRef {
  const SceneNodeRef(this.artboardOrdinal, this.componentIndex);

  final int artboardOrdinal;
  final int componentIndex;

  @override
  bool operator ==(Object other) =>
      other is SceneNodeRef &&
      other.artboardOrdinal == artboardOrdinal &&
      other.componentIndex == componentIndex;

  @override
  int get hashCode => Object.hash(artboardOrdinal, componentIndex);

  @override
  String toString() => 'SceneNodeRef($artboardOrdinal:$componentIndex)';
}

/// UI state of the scene hierarchy: expansion, selection, locks, and
/// search. Purely editor-side; nothing here touches the `.riv` file.
///
/// Locking is an editor concept (the runtime has no lock flag), so locks
/// live here and gate structural operations at the state layer.
class SceneHierarchyController extends ChangeNotifier {
  final Set<SceneNodeRef> _expanded = {};
  final Set<SceneNodeRef> _locked = {};
  SceneNodeRef? _selected;
  String _searchQuery = '';

  SceneNodeRef? get selected => _selected;
  String get searchQuery => _searchQuery;
  bool get isSearching => _searchQuery.isNotEmpty;

  bool isExpanded(SceneNodeRef ref) => _expanded.contains(ref);
  bool isLocked(SceneNodeRef ref) => _locked.contains(ref);

  /// A node is effectively locked when itself or any ancestor is locked.
  bool isEffectivelyLocked(SceneNodeRef ref, List<int> ancestorIndices) {
    if (_locked.contains(ref)) return true;
    return ancestorIndices.any(
      (index) => _locked.contains(SceneNodeRef(ref.artboardOrdinal, index)),
    );
  }

  void toggleExpanded(SceneNodeRef ref) {
    _expanded.contains(ref) ? _expanded.remove(ref) : _expanded.add(ref);
    notifyListeners();
  }

  void expand(SceneNodeRef ref) {
    if (_expanded.add(ref)) notifyListeners();
  }

  void select(SceneNodeRef? ref) {
    if (_selected == ref) return;
    _selected = ref;
    notifyListeners();
  }

  void toggleLocked(SceneNodeRef ref) {
    _locked.contains(ref) ? _locked.remove(ref) : _locked.add(ref);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (_searchQuery == normalized) return;
    _searchQuery = normalized;
    notifyListeners();
  }

  bool matchesSearch(RivHierarchyNode node) {
    if (_searchQuery.isEmpty) return true;
    return node.label.toLowerCase().contains(_searchQuery) ||
        node.typeDisplayName.toLowerCase().contains(_searchQuery);
  }

  /// Whether [node] or any descendant matches the search query.
  bool subtreeMatchesSearch(RivHierarchyNode node) {
    if (matchesSearch(node)) return true;
    return node.children.any(subtreeMatchesSearch);
  }

  /// Migrates all index-keyed state through [remap] after a structural
  /// document change (delete/reorder shift component indices).
  void applyRemap(int artboardOrdinal, Map<int, int> remap) {
    Set<SceneNodeRef> migrate(Set<SceneNodeRef> refs) => {
      for (final ref in refs)
        if (ref.artboardOrdinal != artboardOrdinal)
          ref
        else if ((remap[ref.componentIndex] ?? -1) >= 0)
          SceneNodeRef(artboardOrdinal, remap[ref.componentIndex]!),
    };

    final expanded = migrate(_expanded);
    final locked = migrate(_locked);
    _expanded
      ..clear()
      ..addAll(expanded);
    _locked
      ..clear()
      ..addAll(locked);

    final selected = _selected;
    if (selected != null && selected.artboardOrdinal == artboardOrdinal) {
      final newIndex = remap[selected.componentIndex] ?? -1;
      _selected = newIndex >= 0
          ? SceneNodeRef(artboardOrdinal, newIndex)
          : null;
    }
    notifyListeners();
  }

  /// Resets everything (called when a different document is opened).
  void reset() {
    _expanded.clear();
    _locked.clear();
    _selected = null;
    _searchQuery = '';
    notifyListeners();
  }
}
