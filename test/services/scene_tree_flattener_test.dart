import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/features/editor/state/scene_hierarchy_controller.dart';
import 'package:rive_editor/src/features/editor/state/scene_tree_flattener.dart';
import 'package:rive_editor/src/riv/riv_hierarchy.dart';

RivHierarchyNode _node(int index, String name, [List<RivHierarchyNode>? kids]) {
  final node = RivHierarchyNode(componentIndex: index, typeKey: 2, name: name);
  node.children.addAll(kids ?? const []);
  return node;
}

/// Artboard -> A(1) [B(2), C(3)] , D(4).
List<RivHierarchyNode> _sampleTrees() => [
  _node(0, 'Artboard', [
    _node(1, 'A', [_node(2, 'B'), _node(3, 'C')]),
    _node(4, 'D'),
  ]),
];

void main() {
  group('SceneTreeFlattener', () {
    test('collapsed tree shows only roots', () {
      final controller = SceneHierarchyController();
      final rows = SceneTreeFlattener.flatten(_sampleTrees(), controller);
      expect(rows.map((r) => r.node.name), ['Artboard']);
    });

    test('expansion reveals children with correct depth and ancestors', () {
      final controller = SceneHierarchyController()
        ..expand(const SceneNodeRef(0, 0))
        ..expand(const SceneNodeRef(0, 1));
      final rows = SceneTreeFlattener.flatten(_sampleTrees(), controller);

      expect(rows.map((r) => r.node.name), ['Artboard', 'A', 'B', 'C', 'D']);
      final rowB = rows.firstWhere((r) => r.node.name == 'B');
      expect(rowB.depth, 2);
      expect(rowB.ancestorIndices, [0, 1]);
    });

    test('search shows matching subtrees regardless of expansion', () {
      final controller = SceneHierarchyController()..setSearchQuery('c');
      final rows = SceneTreeFlattener.flatten(_sampleTrees(), controller);
      expect(rows.map((r) => r.node.name), contains('C'));
      expect(rows.map((r) => r.node.name), isNot(contains('D')));
    });

    test('rangeBetween returns visual order inclusive of both ends', () {
      final controller = SceneHierarchyController()
        ..expand(const SceneNodeRef(0, 0))
        ..expand(const SceneNodeRef(0, 1));
      final rows = SceneTreeFlattener.flatten(_sampleTrees(), controller);

      final range = SceneTreeFlattener.rangeBetween(
        rows,
        const SceneNodeRef(0, 1), // A
        const SceneNodeRef(0, 4), // D
      );
      expect(range, [
        const SceneNodeRef(0, 1),
        const SceneNodeRef(0, 2),
        const SceneNodeRef(0, 3),
        const SceneNodeRef(0, 4),
      ]);

      // Reversed anchor/target produces the same set.
      final reversed = SceneTreeFlattener.rangeBetween(
        rows,
        const SceneNodeRef(0, 4),
        const SceneNodeRef(0, 1),
      );
      expect(reversed, range);
    });

    test('flattening 10k nodes stays within the frame budget', () {
      // Broad tree: 100 groups x 100 leaves under one artboard.
      final groups = <RivHierarchyNode>[];
      var index = 1;
      for (var g = 0; g < 100; g++) {
        final groupIndex = index++;
        final leaves = [
          for (var l = 0; l < 100; l++) _node(index++, 'Leaf $g/$l'),
        ];
        groups.add(_node(groupIndex, 'Group $g', leaves));
      }
      final trees = [_node(0, 'Artboard', groups)];

      final controller = SceneHierarchyController()
        ..expand(const SceneNodeRef(0, 0));
      for (final group in groups) {
        controller.expand(SceneNodeRef(0, group.componentIndex));
      }

      final stopwatch = Stopwatch()..start();
      final rows = SceneTreeFlattener.flatten(trees, controller);
      stopwatch.stop();

      expect(rows.length, 1 + 100 + 100 * 100);
      // §4.9: work that may exceed 16ms must move off-thread. Flattening
      // 10k visible rows must stay well inside one frame.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(16),
        reason: 'flatten took ${stopwatch.elapsedMilliseconds}ms',
      );
    });
  });
}
