import '../../../riv/riv_hierarchy.dart';
import 'scene_hierarchy_controller.dart';

/// One visible row of the flattened scene tree.
final class SceneTreeRow {
  const SceneTreeRow({
    required this.ref,
    required this.node,
    required this.depth,
    required this.ancestorIndices,
    required this.hasChildren,
  });

  final SceneNodeRef ref;
  final RivHierarchyNode node;
  final int depth;

  /// Component indices of all ancestors (for effective-lock checks).
  final List<int> ancestorIndices;

  final bool hasChildren;
}

/// Flattens artboard trees into the list of currently visible rows.
///
/// Virtualised rendering (§2.2: 60 fps at 10k nodes) requires a flat,
/// indexable row list so `ListView.builder` touches only on-screen
/// rows. Flattening is pure and runs only when expansion, search, or
/// the document changes, never per frame.
abstract final class SceneTreeFlattener {
  static List<SceneTreeRow> flatten(
    List<RivHierarchyNode> trees,
    SceneHierarchyController controller,
  ) {
    final rows = <SceneTreeRow>[];

    void visit(
      int artboardOrdinal,
      RivHierarchyNode node,
      int depth,
      List<int> ancestors,
    ) {
      if (controller.isSearching && !controller.subtreeMatchesSearch(node)) {
        return;
      }
      final ref = SceneNodeRef(artboardOrdinal, node.componentIndex);
      rows.add(
        SceneTreeRow(
          ref: ref,
          node: node,
          depth: depth,
          ancestorIndices: ancestors,
          hasChildren: node.children.isNotEmpty,
        ),
      );

      // Search shows all matching descendants; otherwise expansion
      // rules. Artboard roots (depth 0) default to expanded so the
      // frame tree is visible without an extra click.
      final expanded =
          controller.isSearching ||
          controller.isExpanded(ref, defaultExpanded: depth == 0);
      if (!expanded) return;
      final childAncestors = [...ancestors, node.componentIndex];
      // Layer order: later siblings draw on top in the runtime, so the
      // panel lists them topmost-first (like Figma's layer list).
      for (final child in node.children.reversed) {
        visit(artboardOrdinal, child, depth + 1, childAncestors);
      }
    }

    for (var i = 0; i < trees.length; i++) {
      visit(i, trees[i], 0, const []);
    }
    return rows;
  }

  /// Rows between [anchor] and [target] inclusive, in visual order
  /// (shift-range selection). Empty when either end is not visible.
  static List<SceneNodeRef> rangeBetween(
    List<SceneTreeRow> rows,
    SceneNodeRef anchor,
    SceneNodeRef target,
  ) {
    var anchorIndex = -1;
    var targetIndex = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].ref == anchor) anchorIndex = i;
      if (rows[i].ref == target) targetIndex = i;
    }
    if (anchorIndex < 0 || targetIndex < 0) return const [];
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    return [for (var i = start; i <= end; i++) rows[i].ref];
  }
}
