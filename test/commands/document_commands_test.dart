import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/commands/command_processor.dart';
import 'package:rive_editor/src/core/commands/command_result.dart';
import 'package:rive_editor/src/core/commands/document_commands.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/editor_command_codec.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_hierarchy.dart';

/// Minimal [DocumentContext] for testing commands without any UI.
final class _TestContext implements DocumentContext {
  _TestContext(Uint8List bytes) : editor = RivDocumentEditor.parse(bytes);

  @override
  final RivDocumentEditor editor;

  final List<(int, Map<int, int>)> reportedRemaps = [];

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {
    reportedRemaps.add((artboardOrdinal, remap));
  }
}

Uint8List _demoBytes() =>
    File('assets/demo/little_machine.riv').readAsBytesSync();

/// Every command type under test, produced against the demo document.
///
/// New command types must be added here; the round-trip suite below
/// runs automatically for each entry (§5.5: every command proves
/// `execute -> undo` byte-identity).
Map<String, EditorCommand Function(_TestContext)> _commandFactories() => {
  RetimeKeyframeCommand.type: (context) {
    final keyframe = context.editor.model.artboards
        .expand((a) => a.animations)
        .expand((a) => a.keyedObjects)
        .expand((o) => o.properties)
        .expand((p) => p.keyframes)
        .firstWhere((k) => k.rawObjectIndex >= 0);
    return RetimeKeyframeCommand(
      rawObjectIndex: keyframe.rawObjectIndex,
      newFrame: keyframe.frame + 5,
      durationFrames: 1000,
    );
  },
  RenameComponentCommand.type: (_) => RenameComponentCommand(
    artboardOrdinal: 0,
    componentIndex: 1,
    newName: 'Renamed',
  ),
  SetComponentHiddenCommand.type: (context) {
    final shape = _findShapeIndex(context);
    return SetComponentHiddenCommand(
      artboardOrdinal: 0,
      componentIndex: shape,
      hidden: true,
    );
  },
  ReparentComponentCommand.type: (context) {
    final tree = RivHierarchy.artboardTrees(context.editor.raw).first;
    return ReparentComponentCommand(
      artboardOrdinal: 0,
      componentIndex: tree.children[1].componentIndex,
      newParentIndex: tree.children[0].componentIndex,
    );
  },
  DuplicateComponentCommand.type: (context) {
    final tree = RivHierarchy.artboardTrees(context.editor.raw).first;
    return DuplicateComponentCommand(
      artboardOrdinal: 0,
      componentIndex: tree.children.first.componentIndex,
    );
  },
  DeleteComponentCommand.type: (context) {
    final tree = RivHierarchy.artboardTrees(context.editor.raw).first;
    return DeleteComponentCommand(
      artboardOrdinal: 0,
      componentIndex: tree.children.first.componentIndex,
    );
  },
  AddArtboardCommand.type: (_) => AddArtboardCommand(name: 'New Board'),
  ImportImageAssetCommand.type: (_) => ImportImageAssetCommand(
    name: 'test.png',
    assetBytes: Uint8List.fromList([9, 9, 9]),
  ),
};

int _findShapeIndex(_TestContext context) {
  final tree = RivHierarchy.artboardTrees(context.editor.raw).first;
  RivHierarchyNode? shape;
  void walk(RivHierarchyNode node) {
    shape ??= node.typeKey == 3 ? node : null;
    node.children.forEach(walk);
  }

  walk(tree);
  return shape?.componentIndex ?? 1;
}

void main() {
  group('command round-trips (execute -> undo is byte-identical)', () {
    for (final entry in _commandFactories().entries) {
      test(entry.key, () {
        final context = _TestContext(_demoBytes());
        final original = context.editor.bytes();
        final command = entry.value(context);

        expect(
          command.execute(context).succeeded,
          isTrue,
          reason: '${entry.key} should execute',
        );
        expect(
          context.editor.bytes(),
          isNot(original),
          reason: '${entry.key} should change the document',
        );

        expect(command.undo(context).succeeded, isTrue);
        expect(
          context.editor.bytes(),
          original,
          reason: '${entry.key} undo must restore identical bytes',
        );
      });
    }
  });

  group('command serialisation', () {
    for (final entry in _commandFactories().entries) {
      test('${entry.key} survives toJson -> decode -> execute', () {
        final context = _TestContext(_demoBytes());
        final command = entry.value(context);

        final decoded = EditorCommandCodec.instance.decode(command.toJson());
        expect(decoded.toJson(), command.toJson());
        expect(decoded.execute(context).succeeded, isTrue);
      });
    }

    test('unknown command type fails loudly', () {
      expect(
        () => EditorCommandCodec.instance.decode({'type': 'nope'}),
        throwsArgumentError,
      );
    });
  });

  group('CommandProcessor', () {
    test('history walks undo and redo, redo cleared by new command', () {
      final context = _TestContext(_demoBytes());
      final processor = CommandProcessor(context: context);
      final original = context.editor.bytes();

      processor.execute(
        RenameComponentCommand(
          artboardOrdinal: 0,
          componentIndex: 1,
          newName: 'One',
        ),
      );
      final afterFirst = context.editor.bytes();
      processor.execute(
        RenameComponentCommand(
          artboardOrdinal: 0,
          componentIndex: 1,
          newName: 'Two',
        ),
      );

      expect(processor.undo().succeeded, isTrue);
      expect(context.editor.bytes(), afterFirst);
      expect(processor.canRedo, isTrue);

      expect(processor.undo().succeeded, isTrue);
      expect(context.editor.bytes(), original);

      expect(processor.redo().succeeded, isTrue);
      expect(context.editor.bytes(), afterFirst);

      // A diverging command clears the redo branch.
      processor.execute(
        RenameComponentCommand(
          artboardOrdinal: 0,
          componentIndex: 1,
          newName: 'Three',
        ),
      );
      expect(processor.canRedo, isFalse);
    });

    test('failed commands never enter the history', () {
      final context = _TestContext(_demoBytes());
      final processor = CommandProcessor(context: context);

      final result = processor.execute(
        DeleteComponentCommand(artboardOrdinal: 0, componentIndex: 0),
      );
      expect(result.succeeded, isFalse);
      expect(result.failure, isA<InvalidMutationFailure>());
      expect(processor.canUndo, isFalse);
    });

    test('mergeable retime commands coalesce into one history entry', () {
      final context = _TestContext(_demoBytes());
      final processor = CommandProcessor(context: context);
      final original = context.editor.bytes();

      final keyframe = context.editor.model.artboards
          .expand((a) => a.animations)
          .expand((a) => a.keyedObjects)
          .expand((o) => o.properties)
          .expand((p) => p.keyframes)
          .firstWhere((k) => k.rawObjectIndex >= 0);

      // Simulates one drag: many intermediate frames.
      for (final frame in [
        keyframe.frame + 1,
        keyframe.frame + 2,
        keyframe.frame + 3,
      ]) {
        processor.execute(
          RetimeKeyframeCommand(
            rawObjectIndex: keyframe.rawObjectIndex,
            newFrame: frame,
            durationFrames: 1000,
          ),
        );
      }

      // One undo restores the original state entirely.
      expect(processor.undo().succeeded, isTrue);
      expect(context.editor.bytes(), original);
      expect(processor.canUndo, isFalse);
    });

    test('structural commands report remaps to the context', () {
      final context = _TestContext(_demoBytes());
      final tree = RivHierarchy.artboardTrees(context.editor.raw).first;

      CommandProcessor(context: context).execute(
        DeleteComponentCommand(
          artboardOrdinal: 0,
          componentIndex: tree.children.first.componentIndex,
        ),
      );
      expect(context.reportedRemaps, isNotEmpty);
      expect(context.reportedRemaps.single.$1, 0);
    });
  });
}
