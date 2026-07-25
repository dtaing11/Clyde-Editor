import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/commands/command_processor.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/editor_command_codec.dart';
import 'package:rive_editor/src/core/commands/property_commands.dart';
import 'package:rive_editor/src/core/model/property_metadata.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_format.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';

final class _TestContext implements DocumentContext {
  _TestContext(Uint8List bytes) : editor = RivDocumentEditor.parse(bytes);

  @override
  final RivDocumentEditor editor;

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {}
}

/// Blank document with one factory shape (component index 1 = Shape).
Uint8List _documentWithShape() {
  final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
  RivShapeFactory.addShape(
    raw,
    artboardOrdinal: 0,
    kind: RivShapeKind.rectangle,
    name: 'R',
    x: 100,
    y: 100,
    width: 50,
    height: 50,
    color: 0xFF000000,
  );
  return raw.serialize();
}

double _shapeX(RivDocumentEditor editor) {
  final shape = editor.raw.objects.firstWhere(
    (o) => o.typeKey == RivTypeKeys.shape,
  );
  return shape.property(RivPropertyKeys.nodeX)!.floatValue;
}

void main() {
  group('SetComponentPropertyCommand', () {
    test('updates an existing float property', () {
      final context = _TestContext(_documentWithShape());
      final command = SetComponentPropertyCommand(
        artboardOrdinal: 0,
        componentIndex: 1,
        propertyKey: RivPropertyKeys.nodeX,
        value: 240,
      );
      expect(command.execute(context).succeeded, isTrue);
      expect(_shapeX(context.editor), 240);
    });

    test('adds a missing property (rotation on a fresh shape)', () {
      final context = _TestContext(_documentWithShape());
      final command = SetComponentPropertyCommand(
        artboardOrdinal: 0,
        componentIndex: 1,
        propertyKey: 15, // rotation, absent on factory shapes
        value: 0.5,
      );
      expect(command.execute(context).succeeded, isTrue);

      final reparsed = RivRawDocument.parse(context.editor.bytes());
      final shape = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.shape,
      );
      expect(shape.property(15)!.floatValue, closeTo(0.5, 1e-6));
    });

    test('execute -> undo restores byte-identical document', () {
      final context = _TestContext(_documentWithShape());
      final original = context.editor.bytes();
      final command = SetComponentPropertyCommand(
        artboardOrdinal: 0,
        componentIndex: 1,
        propertyKey: RivPropertyKeys.nodeX,
        value: 999,
      );
      expect(command.execute(context).succeeded, isTrue);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.bytes(), original);
    });

    test('no-op value is rejected and stays out of history', () {
      final context = _TestContext(_documentWithShape());
      final processor = CommandProcessor(context: context);
      final result = processor.execute(
        SetComponentPropertyCommand(
          artboardOrdinal: 0,
          componentIndex: 1,
          propertyKey: RivPropertyKeys.nodeX,
          value: 100, // Unchanged.
        ),
      );
      expect(result.succeeded, isFalse);
      expect(processor.canUndo, isFalse);
    });

    test('drag sequence merges into one undo entry restoring origin', () {
      final context = _TestContext(_documentWithShape());
      final processor = CommandProcessor(context: context);
      final original = context.editor.bytes();

      for (final value in [110.0, 120.0, 130.0]) {
        processor.execute(
          SetComponentPropertyCommand(
            artboardOrdinal: 0,
            componentIndex: 1,
            propertyKey: RivPropertyKeys.nodeX,
            value: value,
          ),
        );
      }
      expect(_shapeX(context.editor), 130);

      expect(processor.undo().succeeded, isTrue);
      expect(context.editor.bytes(), original);
      expect(processor.canUndo, isFalse);
    });

    test('survives toJson -> decode -> execute', () {
      final context = _TestContext(_documentWithShape());
      final command = SetComponentPropertyCommand(
        artboardOrdinal: 0,
        componentIndex: 1,
        propertyKey: RivPropertyKeys.nodeY,
        value: 42,
      );
      final decoded = EditorCommandCodec.instance.decode(command.toJson());
      expect(decoded.toJson(), command.toJson());
      expect(decoded.execute(context).succeeded, isTrue);
    });

    test('missing component fails with typed failure', () {
      final context = _TestContext(_documentWithShape());
      final result = SetComponentPropertyCommand(
        artboardOrdinal: 0,
        componentIndex: 99,
        propertyKey: RivPropertyKeys.nodeX,
        value: 1,
      ).execute(context);
      expect(result.succeeded, isFalse);
    });
  });

  group('PropertyMetadataRegistry', () {
    test('standard registry covers shapes and parametric paths', () {
      final registry = PropertyMetadataRegistry.standard();
      final shapeProperties = registry.forType(RivTypeKeys.shape);
      expect(shapeProperties.map((p) => p.label), contains('X'));
      expect(shapeProperties.map((p) => p.label), contains('Opacity'));

      final rectProperties = registry.forType(RivTypeKeys.rectangle);
      expect(rectProperties.map((p) => p.label), contains('Width'));

      expect(registry.forType(999), isEmpty);
    });

    test('registration is open for extension', () {
      final registry = PropertyMetadataRegistry();
      const custom = PropertyDescriptor(key: 1234, label: 'Custom', group: 'X');
      registry.register(77, const [custom]);
      expect(registry.forType(77).single.label, 'Custom');
    });
  });
}
