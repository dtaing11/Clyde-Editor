import 'package:flutter/foundation.dart';

import '../../../core/model/scene_node_ref.dart';
import '../../../riv/riv_hierarchy.dart';

export '../../../core/model/scene_node_ref.dart';

/// UI state of the scene hierarchy: expansion, locks, and search.
/// Purely editor-side; nothing here touches the `.riv` file.
///
/// Selection lives in the shared `SelectionService` (§2.2: one
/// selection across hierarchy, canvas, and inspector), not here.
/// Locking is an editor concept (the runtime has no lock flag), so
/// locks live here and gate structural operations at the state layer.
class SceneHierarchyController extends ChangeNotifier {
  /// Explicit expansion overrides; nodes absent here use their default
  /// ([defaultExpanded], true for artboard roots so frames start open).
  final Map<SceneNodeRef, bool> _expansionOverrides = {};
  final Set<SceneNodeRef> _locked = {};
  String _searchQuery = '';

  String get searchQuery => _searchQuery;
  bool get isSearching => _searchQuery.isNotEmpty;

  bool isExpanded(SceneNodeRef ref, {bool defaultExpanded = false}) =>
      _expansionOverrides[ref] ?? defaultExpanded;
  bool isLocked(SceneNodeRef ref) => _locked.contains(ref);

  /// A node is effectively locked when itself or any ancestor is locked.
  bool isEffectivelyLocked(SceneNodeRef ref, List<int> ancestorIndices) {
    if (_locked.contains(ref)) return true;
    return ancestorIndices.any(
      (index) => _locked.contains(SceneNodeRef(ref.artboardOrdinal, index)),
    );
  }

  void toggleExpanded(SceneNodeRef ref, {bool defaultExpanded = false}) {
    _expansionOverrides[ref] = !isExpanded(
      ref,
      defaultExpanded: defaultExpanded,
    );
    notifyListeners();
  }

  void expand(SceneNodeRef ref) {
    if (_expansionOverrides[ref] == true) return;
    _expansionOverrides[ref] = true;
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

    final overrides = <SceneNodeRef, bool>{
      for (final entry in _expansionOverrides.entries)
        if (entry.key.artboardOrdinal != artboardOrdinal)
          entry.key: entry.value
        else if ((remap[entry.key.componentIndex] ?? -1) >= 0)
          SceneNodeRef(artboardOrdinal, remap[entry.key.componentIndex]!):
              entry.value,
    };
    final locked = migrate(_locked);
    _expansionOverrides
      ..clear()
      ..addAll(overrides);
    _locked
      ..clear()
      ..addAll(locked);
    notifyListeners();
  }

  /// Resets everything (called when a different document is opened).
  void reset() {
    _expansionOverrides.clear();
    _locked.clear();
    _searchQuery = '';
    notifyListeners();
  }
}
