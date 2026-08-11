import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/commands/animation_commands.dart';
import 'package:rive_editor/src/core/commands/command_processor.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/commands/editor_command_codec.dart';
import 'package:rive_editor/src/riv/riv_animation_factory.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_format.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';
import 'package:rive_editor/src/riv/riv_parser.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';

final class _TestContext implements DocumentContext {
  _TestContext(Uint8List bytes) : editor = RivDocumentEditor.parse(bytes);

  @override
  final RivDocumentEditor editor;

  @override
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap) {}
}

/// Blank document with one shape (component 1) for keyframing.
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

void main() {
  group('RivAnimationFactory.addAnimation', () {
    test('creates an animation visible to the display parser', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      expect(
        RivAnimationFactory.addAnimation(
          raw,
          artboardOrdinal: 0,
          name: 'Bounce',
          fps: 30,
          durationFrames: 90,
        ),
        isTrue,
      );

      final model = RivParser.parse(raw.serialize());
      final animation = model.artboards.single.animations.single;
      expect(animation.name, 'Bounce');
      expect(animation.fps, 30);
      expect(animation.durationFrames, 90);
    });

    test('fails for a missing artboard', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      expect(
        RivAnimationFactory.addAnimation(raw, artboardOrdinal: 7, name: 'X'),
        isFalse,
      );
    });

    test('does not shift component indices', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      final namesBefore = RivParser.fromRaw(
        raw,
      ).artboards.single.componentNames;
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      final namesAfter = RivParser.parse(
        raw.serialize(),
      ).artboards.single.componentNames;
      expect(namesAfter, namesBefore);
    });
  });

  group('RivAnimationFactory.insertKeyframe', () {
    RivRawDocument animatedDocument() {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      return raw;
    }

    test('creates keyed object, property, and keyframe on first key', () {
      final raw = animatedDocument();
      expect(
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13, // nodeX
          frame: 10,
          value: 200,
        ),
        isTrue,
      );

      final animation = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single;
      final keyed = animation.keyedObjects.single;
      expect(keyed.objectId, 1);
      final property = keyed.properties.single;
      expect(property.propertyKey, 13);
      final keyframe = property.keyframes.single;
      expect(keyframe.frame, 10);
      expect(keyframe.value, 200);
    });

    test('keeps keyframes in ascending frame order', () {
      final raw = animatedDocument();
      for (final frame in [30, 10, 20]) {
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13,
          frame: frame,
          value: frame.toDouble(),
        );
      }
      final property = RivParser.parse(raw.serialize())
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single;
      expect(property.keyframes.map((k) => k.frame), [10, 20, 30]);
    });

    test('replaces the value of an existing keyframe at the same frame', () {
      final raw = animatedDocument();
      for (final value in [5.0, 9.0]) {
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13,
          frame: 4,
          value: value,
        );
      }
      final property = RivParser.parse(raw.serialize())
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single;
      expect(property.keyframes.single.value, 9);
    });

    test('separate properties key under the same keyed object', () {
      final raw = animatedDocument();
      for (final key in [13, 14]) {
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: key,
          frame: 0,
          value: 1,
        );
      }
      final keyed = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single.keyedObjects.single;
      expect(keyed.properties.map((p) => p.propertyKey), [13, 14]);
    });
  });

  group('animation commands', () {
    test('AddAnimationCommand executes with byte-identity undo', () {
      final context = _TestContext(_documentWithShape());
      final before = context.editor.raw.serialize();
      final command = AddAnimationCommand(artboardOrdinal: 0, name: 'Walk');
      expect(command.execute(context).succeeded, isTrue);
      expect(
        RivParser.fromRaw(context.editor.raw).artboards.single.animations,
        hasLength(1),
      );
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);
    });

    test('InsertKeyframeCommand merges same-frame value adjustments', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      final processor = CommandProcessor(
        context: _TestContext(raw.serialize()),
      );

      for (final value in [10.0, 20.0]) {
        processor.execute(
          InsertKeyframeCommand(
            artboardOrdinal: 0,
            animationOrdinal: 0,
            objectId: 1,
            propertyKey: 13,
            frame: 5,
            value: value,
          ),
        );
      }
      processor.undo();
      expect(processor.canUndo, isFalse);
    });

    test('commands round-trip through the codec', () {
      final add = AddAnimationCommand(
        artboardOrdinal: 1,
        name: 'Run',
        fps: 24,
        durationFrames: 48,
      );
      final decodedAdd =
          EditorCommandCodec.instance.decode(add.toJson())
              as AddAnimationCommand;
      expect(decodedAdd.name, 'Run');
      expect(decodedAdd.fps, 24);

      final insert = InsertKeyframeCommand(
        artboardOrdinal: 0,
        animationOrdinal: 2,
        objectId: 3,
        propertyKey: 14,
        frame: 12,
        value: 6.5,
      );
      final decodedInsert =
          EditorCommandCodec.instance.decode(insert.toJson())
              as InsertKeyframeCommand;
      expect(decodedInsert.animationOrdinal, 2);
      expect(decodedInsert.value, 6.5);
    });
  });
  group('RivAnimationFactory.deleteKeyframe', () {
    RivRawDocument keyedDocument({int keyframes = 2, int properties = 1}) {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      for (var p = 0; p < properties; p++) {
        for (var k = 0; k < keyframes; k++) {
          RivAnimationFactory.insertKeyframe(
            raw,
            artboardOrdinal: 0,
            animationOrdinal: 0,
            objectId: 1,
            propertyKey: 13 + p,
            frame: k * 10,
            value: k.toDouble(),
          );
        }
      }
      return raw;
    }

    int keyframeIndexAt(RivRawDocument raw, int frame) {
      for (var i = 0; i < raw.objects.length; i++) {
        final object = raw.objects[i];
        if (object.typeKey != RivTypeKeys.keyFrameDouble) continue;
        final f = object.property(RivPropertyKeys.keyFrameFrame);
        if ((f?.uintValue ?? 0) == frame) return i;
      }
      return -1;
    }

    test('removes one keyframe, keeping siblings', () {
      final raw = keyedDocument();
      expect(
        RivAnimationFactory.deleteKeyframe(raw, keyframeIndexAt(raw, 10)),
        isTrue,
      );
      final property = RivParser.parse(raw.serialize())
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single;
      expect(property.keyframes.map((k) => k.frame), [0]);
    });

    test('prunes empty KeyedProperty and KeyedObject', () {
      final raw = keyedDocument(keyframes: 1);
      RivAnimationFactory.deleteKeyframe(raw, keyframeIndexAt(raw, 0));
      final animation = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single;
      expect(animation.keyedObjects, isEmpty);
      expect(
        raw.objects.any((o) => o.typeKey == RivTypeKeys.keyedObject),
        isFalse,
      );
      expect(
        raw.objects.any((o) => o.typeKey == RivTypeKeys.keyedProperty),
        isFalse,
      );
    });

    test('keeps the KeyedObject when another property remains', () {
      final raw = keyedDocument(keyframes: 1, properties: 2);
      RivAnimationFactory.deleteKeyframe(raw, keyframeIndexAt(raw, 0));
      final keyed = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single.keyedObjects.single;
      expect(keyed.properties, hasLength(1));
      expect(keyed.properties.single.propertyKey, 14);
    });

    test('rejects non-keyframe indices', () {
      final raw = keyedDocument();
      expect(RivAnimationFactory.deleteKeyframe(raw, 0), isFalse);
      expect(RivAnimationFactory.deleteKeyframe(raw, 999), isFalse);
    });

    test('DeleteKeyframeCommand executes with byte-identity undo', () {
      final raw = keyedDocument();
      final context = _TestContext(raw.serialize());
      final before = context.editor.raw.serialize();
      final index = keyframeIndexAt(context.editor.raw, 10);
      final command = DeleteKeyframeCommand(rawObjectIndex: index);
      expect(command.execute(context).succeeded, isTrue);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);
    });
  });
  group('loop modes', () {
    test('new animations author loop and parser reads it back', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      final animation = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single;
      expect(animation.loop, RivLoopMode.loop);
    });

    test('setAnimationUint changes the loop value', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      expect(
        RivAnimationFactory.setAnimationUint(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          propertyKey: RivPropertyKeys.animationLoop,
          value: RivLoopMode.pingPong.value,
        ),
        isTrue,
      );
      final animation = RivParser.parse(
        raw.serialize(),
      ).artboards.single.animations.single;
      expect(animation.loop, RivLoopMode.pingPong);
    });

    test('setAnimationUint fails for a missing animation', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      expect(
        RivAnimationFactory.setAnimationUint(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 3,
          propertyKey: RivPropertyKeys.animationLoop,
          value: 0,
        ),
        isFalse,
      );
    });

    test('SetAnimationUintCommand round-trips with byte-identity undo', () {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      final context = _TestContext(raw.serialize());
      final before = context.editor.raw.serialize();

      final command = SetAnimationUintCommand(
        artboardOrdinal: 0,
        animationOrdinal: 0,
        propertyKey: RivPropertyKeys.animationLoop,
        value: RivLoopMode.oneShot.value,
      );
      expect(command.execute(context).succeeded, isTrue);
      expect(
        RivParser.fromRaw(
          context.editor.raw,
        ).artboards.single.animations.single.loop,
        RivLoopMode.oneShot,
      );
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);

      final decoded =
          EditorCommandCodec.instance.decode(command.toJson())
              as SetAnimationUintCommand;
      expect(decoded.value, RivLoopMode.oneShot.value);
    });
  });
}
