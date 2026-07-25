import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/editor_command_codec.dart';
import 'package:rive_editor/src/core/commands/shape_commands.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_format.dart';
import 'package:rive_editor/src/riv/riv_hierarchy.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';

final class _TestContext implements DocumentContext {
  _TestContext(Uint8List bytes) : editor = RivDocumentEditor.parse(bytes);

  @override
  final RivDocumentEditor editor;

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {}
}

Uint8List _blankDocument() => RivDocumentBuilder.newDocument();

AddShapeCommand _rectangleCommand() => AddShapeCommand(
  artboardOrdinal: 0,
  kind: RivShapeKind.rectangle,
  name: 'Rect 1',
  x: 100,
  y: 80,
  width: 120,
  height: 60,
  color: 0xFFAA5500,
);

void main() {
  _polygonAndTextTests();
  group('RivShapeFactory', () {
    test('recipe includes a stroke outline with black solid color', () {
      final raw = RivRawDocument.parse(_blankDocument());
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.rectangle,
        name: 'Outlined',
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        color: 0xFFFFFFFF,
      );
      final reparsed = RivRawDocument.parse(raw.serialize());
      final stroke = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.stroke,
      );
      expect(
        stroke.property(RivPropertyKeys.strokeThickness)!.floatValue,
        RivShapeFactory.defaultStrokeThickness,
      );
      // Two solid colors: fill + stroke; stroke's is black.
      final colors = reparsed.objects
          .where((o) => o.typeKey == RivTypeKeys.solidColor)
          .toList();
      expect(colors, hasLength(2));
      expect(
        colors.last.property(RivPropertyKeys.solidColorValue) != null,
        isTrue,
      );
    });

    test('rectangle recipe re-parses with exact objects and values', () {
      final raw = RivRawDocument.parse(_blankDocument());
      final added = RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.rectangle,
        name: 'Rect 1',
        x: 100,
        y: 80,
        width: 120,
        height: 60,
        color: 0xFFAA5500,
      );
      expect(added, isTrue);

      final reparsed = RivRawDocument.parse(raw.serialize());
      final types = reparsed.objects.map((o) => o.typeKey).toList();
      expect(
        types,
        containsAllInOrder([
          RivTypeKeys.artboard,
          RivTypeKeys.shape,
          RivTypeKeys.rectangle,
          RivTypeKeys.fill,
          RivTypeKeys.solidColor,
        ]),
      );

      final shape = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.shape,
      );
      expect(shape.property(RivPropertyKeys.nodeX)!.floatValue, 100);
      expect(shape.property(RivPropertyKeys.nodeY)!.floatValue, 80);

      final rect = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.rectangle,
      );
      expect(rect.property(RivPropertyKeys.parametricWidth)!.floatValue, 120);
      expect(rect.property(RivPropertyKeys.parametricHeight)!.floatValue, 60);
    });

    test('parent links form Shape<-Path and Shape<-Fill<-SolidColor', () {
      final raw = RivRawDocument.parse(_blankDocument());
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.ellipse,
        name: 'Ellipse 1',
        x: 0,
        y: 0,
        width: 50,
        height: 50,
        color: 0xFFFFFFFF,
      );

      final tree = RivHierarchy.artboardTrees(raw).single;
      final shape = tree.children.singleWhere(
        (n) => n.typeKey == RivTypeKeys.shape,
      );
      final childTypes = shape.children.map((n) => n.typeKey).toSet();
      expect(childTypes, contains(RivTypeKeys.ellipse));
      expect(childTypes, contains(RivTypeKeys.fill));

      final fill = shape.children.singleWhere(
        (n) => n.typeKey == RivTypeKeys.fill,
      );
      expect(fill.children.single.typeKey, RivTypeKeys.solidColor);
    });

    test('adds into the correct artboard of a multi-artboard document', () {
      final raw = RivRawDocument.parse(_blankDocument());
      RivDocumentBuilder.appendArtboard(raw, name: 'Second');
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 1,
        kind: RivShapeKind.rectangle,
        name: 'OnSecond',
        x: 1,
        y: 2,
        width: 3,
        height: 4,
        color: 0xFF000000,
      );

      final trees = RivHierarchy.artboardTrees(
        RivRawDocument.parse(raw.serialize()),
      );
      expect(trees[0].children, isEmpty);
      expect(trees[1].children.map((n) => n.name), contains('OnSecond'));
    });

    test('fails cleanly for a missing artboard', () {
      final raw = RivRawDocument.parse(_blankDocument());
      expect(
        RivShapeFactory.addShape(
          raw,
          artboardOrdinal: 9,
          kind: RivShapeKind.rectangle,
          name: 'x',
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          color: 0,
        ),
        isFalse,
      );
    });

    test('works on real files (little_machine.riv)', () {
      final raw = RivRawDocument.parse(
        File('assets/demo/little_machine.riv').readAsBytesSync(),
      );
      final before = RivHierarchy.artboardTrees(raw).first.children.length;
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.rectangle,
        name: 'Added',
        x: 10,
        y: 10,
        width: 40,
        height: 40,
        color: 0xFF123456,
      );
      final after = RivHierarchy.artboardTrees(
        RivRawDocument.parse(raw.serialize()),
      ).first.children.length;
      expect(after, before + 1);
    });
  });

  group('AddShapeCommand', () {
    test('execute -> undo restores byte-identical document', () {
      final context = _TestContext(_blankDocument());
      final original = context.editor.bytes();
      final command = _rectangleCommand();

      expect(command.execute(context).succeeded, isTrue);
      expect(context.editor.bytes(), isNot(original));
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.bytes(), original);
    });

    test('survives toJson -> decode -> execute', () {
      final context = _TestContext(_blankDocument());
      final command = _rectangleCommand();
      final decoded = EditorCommandCodec.instance.decode(command.toJson());
      expect(decoded.toJson(), command.toJson());
      expect(decoded.execute(context).succeeded, isTrue);
    });

    test('fails with typed failure for a missing artboard', () {
      final context = _TestContext(_blankDocument());
      final command = AddShapeCommand(
        artboardOrdinal: 5,
        kind: RivShapeKind.rectangle,
        name: 'x',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      );
      final result = command.execute(context);
      expect(result.succeeded, isFalse);
    });
  });
}

// -- Polygon and text ------------------------------------------------------

void _polygonAndTextTests() {
  group('polygon', () {
    test('recipe re-parses with points property', () {
      final raw = RivRawDocument.parse(_blankDocument());
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.polygon,
        name: 'Penta',
        x: 50,
        y: 50,
        width: 80,
        height: 80,
        color: 0xFF00FF00,
        polygonPoints: 6,
      );
      final reparsed = RivRawDocument.parse(raw.serialize());
      final polygon = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.polygon,
      );
      expect(polygon.property(RivPropertyKeys.polygonPoints)!.uintValue, 6);
    });

    test('AddShapeCommand supports polygon kind with undo byte-identity', () {
      final context = _TestContext(_blankDocument());
      final original = context.editor.bytes();
      final command = AddShapeCommand(
        artboardOrdinal: 0,
        kind: RivShapeKind.polygon,
        name: 'P',
        x: 10,
        y: 10,
        width: 40,
        height: 40,
      );
      expect(command.execute(context).succeeded, isTrue);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.bytes(), original);
    });
  });

  group('text', () {
    Uint8List fakeFont() => Uint8List.fromList(List.filled(64, 7));

    test('recipe embeds font asset and builds the text tree', () {
      final raw = RivRawDocument.parse(_blankDocument());
      final added = RivShapeFactory.addText(
        raw,
        artboardOrdinal: 0,
        name: 'Title',
        text: 'Hello',
        x: 100,
        y: 60,
        fontSize: 24,
        color: 0xFFFFFFFF,
        fontBytes: fakeFont(),
        fontName: 'TestFont',
      );
      expect(added, isTrue);

      final reparsed = RivRawDocument.parse(raw.serialize());
      final types = reparsed.objects.map((o) => o.typeKey).toList();
      expect(types, contains(RivTypeKeys.fontAsset));
      expect(types, contains(RivTypeKeys.fileAssetContents));
      expect(types, contains(RivTypeKeys.text));
      expect(types, contains(RivTypeKeys.textStylePaint));
      expect(types, contains(RivTypeKeys.textValueRun));

      final run = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.textValueRun,
      );
      final style = reparsed.objects.firstWhere(
        (o) => o.typeKey == RivTypeKeys.textStylePaint,
      );
      expect(style.property(RivPropertyKeys.textStyleFontSize)!.floatValue, 24);
      // The run must reference the style's component index.
      expect(
        run.property(RivPropertyKeys.textRunStyleId)!.uintValue,
        greaterThan(0),
      );
    });

    test('same font embeds once across two text objects', () {
      final raw = RivRawDocument.parse(_blankDocument());
      for (var i = 0; i < 2; i++) {
        RivShapeFactory.addText(
          raw,
          artboardOrdinal: 0,
          name: 'T$i',
          text: 'x',
          x: 0,
          y: 0,
          fontSize: 12,
          color: 0xFF000000,
          fontBytes: fakeFont(),
          fontName: 'TestFont',
        );
      }
      final fontAssets = raw.objects
          .where((o) => o.typeKey == RivTypeKeys.fontAsset)
          .length;
      expect(fontAssets, 1, reason: 'font must be deduplicated by name');
    });

    test('AddTextCommand undo byte-identity and serialisation', () {
      final context = _TestContext(_blankDocument());
      final original = context.editor.bytes();
      final command = AddTextCommand(
        artboardOrdinal: 0,
        name: 'T',
        text: 'Hi',
        x: 5,
        y: 5,
        fontBytes: fakeFont(),
        fontName: 'TestFont',
      );
      expect(command.execute(context).succeeded, isTrue);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.bytes(), original);

      final decoded = EditorCommandCodec.instance.decode(command.toJson());
      expect(decoded.toJson(), command.toJson());
      expect(decoded.execute(context).succeeded, isTrue);
    });
  });
}
