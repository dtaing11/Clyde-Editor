import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/riv/riv_artboard_editor.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_format.dart';
import 'package:rive_editor/src/riv/riv_hierarchy.dart';
import 'package:rive_editor/src/riv/riv_parser.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';

Uint8List _loadAsset(String name) =>
    File('assets/demo/$name').readAsBytesSync();

void main() {
  group('RivDocumentBuilder', () {
    test('new document parses in raw document and display parser', () {
      final bytes = RivDocumentBuilder.newDocument(artboardName: 'Board');
      final raw = RivRawDocument.parse(bytes);
      expect(raw.majorVersion, 7);
      expect(raw.objects, hasLength(2)); // Backboard + artboard.

      final model = RivParser.parse(bytes);
      expect(model.artboards, hasLength(1));
      expect(model.artboards.single.name, 'Board');
    });

    test('new document round-trips byte-identically', () {
      final bytes = RivDocumentBuilder.newDocument();
      expect(RivRawDocument.parse(bytes).serialize(), bytes);
    });

    test('new document with background writes fill and solid color', () {
      final bytes = RivDocumentBuilder.newDocument(backgroundColor: 0xFF102030);
      final raw = RivRawDocument.parse(bytes);
      // Backboard + artboard + fill + solid color.
      expect(raw.objects, hasLength(4));
      expect(raw.objects[2].typeKey, RivTypeKeys.fill);
      expect(raw.objects[3].typeKey, RivTypeKeys.solidColor);
      expect(raw.serialize(), bytes);
      // Display parser still sees exactly one artboard.
      expect(RivParser.parse(bytes).artboards, hasLength(1));
    });

    test('appendArtboard with background parses cleanly', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      RivDocumentBuilder.appendArtboard(
        raw,
        name: 'Tinted',
        backgroundColor: 0xFFFF0000,
      );
      final model = RivParser.parse(raw.serialize());
      expect(model.artboards.map((a) => a.name), ['Artboard', 'Tinted']);
    });

    test('appendArtboard adds a second artboard preserving the first', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      RivDocumentBuilder.appendArtboard(raw, name: 'Second');

      final model = RivParser.fromRaw(raw);
      expect(model.artboards.map((a) => a.name), ['Artboard', 'Second']);

      // Reserializes and reparses cleanly.
      final reparsed = RivParser.parse(raw.serialize());
      expect(reparsed.artboards, hasLength(2));
    });

    test('appendArtboard works on real files', () {
      final raw = RivRawDocument.parse(_loadAsset('little_machine.riv'));
      final before = RivParser.fromRaw(raw).artboards.length;
      RivDocumentBuilder.appendArtboard(raw, name: 'Extra');
      final after = RivParser.parse(raw.serialize()).artboards;
      expect(after, hasLength(before + 1));
      expect(after.last.name, 'Extra');
    });

    test('embedImageAsset inserts asset visible to RivHierarchy', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      RivDocumentBuilder.embedImageAsset(
        raw,
        name: 'hero.png',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        assetId: RivDocumentBuilder.nextAssetId(raw),
      );

      final assets = RivHierarchy.assets(raw);
      expect(assets, hasLength(1));
      expect(assets.single.name, 'hero.png');
      expect(assets.single.isEmbedded, isTrue);
      expect(assets.single.assetId, 0);

      // Still parses after serialization.
      expect(RivParser.parse(raw.serialize()).artboards, isNotEmpty);
    });
  });

  group('RivHierarchy', () {
    test('builds parent/child tree from little_machine.riv', () {
      final raw = RivRawDocument.parse(_loadAsset('little_machine.riv'));
      final trees = RivHierarchy.artboardTrees(raw);
      expect(trees, isNotEmpty);

      final root = trees.first;
      expect(root.componentIndex, 0);
      expect(
        root.children,
        isNotEmpty,
        reason: 'artboard should have children',
      );

      // Every reachable node's index is unique.
      final seen = <int>{};
      void walk(RivHierarchyNode node) {
        expect(seen.add(node.componentIndex), isTrue);
        node.children.forEach(walk);
      }

      walk(root);
      expect(seen.length, greaterThan(2));
    });
  });

  group('RivArtboardEditor', () {
    RivRawDocument load() =>
        RivRawDocument.parse(_loadAsset('little_machine.riv'));

    test('rename persists through serialization', () {
      final raw = load();
      final editor = RivArtboardEditor(raw, 0);
      expect(editor.rename(1, 'Renamed Node'), isTrue);

      final trees = RivHierarchy.artboardTrees(
        RivRawDocument.parse(raw.serialize()),
      );
      final names = <String>[];
      void walk(RivHierarchyNode node) {
        names.add(node.name);
        node.children.forEach(walk);
      }

      walk(trees.first);
      expect(names, contains('Renamed Node'));
    });

    test('delete removes subtree and file stays consistent', () {
      final raw = load();
      final treesBefore = RivHierarchy.artboardTrees(raw);
      final victim = treesBefore.first.children.first;
      final subtreeSize = _count(victim);

      final result = RivArtboardEditor(raw, 0).delete(victim.componentIndex);
      expect(result.succeeded, isTrue);
      expect(result.remap[victim.componentIndex], -1);

      final reparsed = RivRawDocument.parse(raw.serialize());
      final treesAfter = RivHierarchy.artboardTrees(reparsed);
      expect(
        _count(treesAfter.first),
        lessThanOrEqualTo(_count(treesBefore.first) - subtreeSize),
      );
      // Display parser also still succeeds (keyed data healed).
      expect(RivParser.fromRaw(reparsed).artboards, isNotEmpty);
    });

    test('duplicate appends a copy with remapped internal references', () {
      final raw = load();
      final treesBefore = RivHierarchy.artboardTrees(raw);
      final source = treesBefore.first.children.first;
      final sizeBefore = _count(treesBefore.first);

      final result = RivArtboardEditor(raw, 0).duplicate(source.componentIndex);
      expect(result.succeeded, isTrue);

      final treesAfter = RivHierarchy.artboardTrees(
        RivRawDocument.parse(raw.serialize()),
      );
      expect(_count(treesAfter.first), sizeBefore + _count(source));

      final names = <String>[];
      void walk(RivHierarchyNode node) {
        names.add(node.label);
        node.children.forEach(walk);
      }

      walk(treesAfter.first);
      expect(names.where((n) => n.endsWith('copy')), isNotEmpty);
    });

    test('reparent moves node under new parent', () {
      final raw = load();
      final tree = RivHierarchy.artboardTrees(raw).first;
      // Need at least two root children to move one under the other.
      if (tree.children.length < 2) return;

      final moved = tree.children[1];
      final newParent = tree.children[0];
      final result = RivArtboardEditor(
        raw,
        0,
      ).reparent(moved.componentIndex, newParent.componentIndex);
      expect(result.succeeded, isTrue);

      final after = RivHierarchy.artboardTrees(
        RivRawDocument.parse(raw.serialize()),
      ).first;
      final newParentAfter = _find(after, (n) => n.label == newParent.label);
      expect(newParentAfter, isNotNull);
      expect(
        newParentAfter!.children.map((c) => c.label),
        contains(moved.label),
      );
    });

    test('reparent into own subtree is rejected', () {
      final raw = load();
      final tree = RivHierarchy.artboardTrees(raw).first;
      final parent = tree.children.first;
      if (parent.children.isEmpty) return;

      final result = RivArtboardEditor(
        raw,
        0,
      ).reparent(parent.componentIndex, parent.children.first.componentIndex);
      expect(result.succeeded, isFalse);
    });

    test('hide sets and clears the drawable Hidden flag', () {
      final raw = load();
      final editor = RivArtboardEditor(raw, 0);
      final tree = RivHierarchy.artboardTrees(raw).first;
      final target = _find(tree, (n) => n.typeKey == 3); // A shape.
      if (target == null) return;

      expect(editor.isHidden(target.componentIndex), isFalse);
      expect(editor.setHidden(target.componentIndex, true), isTrue);
      expect(editor.isHidden(target.componentIndex), isTrue);
      expect(editor.setHidden(target.componentIndex, false), isTrue);
      expect(editor.isHidden(target.componentIndex), isFalse);
    });
  });
}

int _count(RivHierarchyNode node) =>
    1 + node.children.fold(0, (sum, child) => sum + _count(child));

RivHierarchyNode? _find(
  RivHierarchyNode node,
  bool Function(RivHierarchyNode) predicate,
) {
  if (predicate(node)) return node;
  for (final child in node.children) {
    final found = _find(child, predicate);
    if (found != null) return found;
  }
  return null;
}
