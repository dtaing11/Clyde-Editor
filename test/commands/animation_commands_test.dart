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
import 'package:rive_editor/src/riv/riv_keyframe_evaluator.dart';
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
  group('SetKeyframeValueCommand', () {
    RivRawDocument keyed() {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      RivAnimationFactory.insertKeyframe(
        raw,
        artboardOrdinal: 0,
        animationOrdinal: 0,
        objectId: 1,
        propertyKey: 13,
        frame: 5,
        value: 42,
      );
      return raw;
    }

    int keyframeIndex(RivRawDocument raw) {
      for (var i = 0; i < raw.objects.length; i++) {
        if (raw.objects[i].typeKey == RivTypeKeys.keyFrameDouble) return i;
      }
      return -1;
    }

    test('changes the value with byte-identity undo', () {
      final context = _TestContext(keyed().serialize());
      final before = context.editor.raw.serialize();
      final index = keyframeIndex(context.editor.raw);
      final command = SetKeyframeValueCommand(rawObjectIndex: index, value: 99);
      expect(command.execute(context).succeeded, isTrue);
      final keyframe = RivParser.fromRaw(context.editor.raw)
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single
          .keyframes
          .single;
      expect(keyframe.value, 99);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);
    });

    test('merges continuous drags into one entry', () {
      final context = _TestContext(keyed().serialize());
      final processor = CommandProcessor(context: context);
      final index = keyframeIndex(context.editor.raw);
      for (final value in [50.0, 60.0, 70.0]) {
        processor.execute(
          SetKeyframeValueCommand(rawObjectIndex: index, value: value),
        );
      }
      processor.undo();
      expect(processor.canUndo, isFalse);
    });

    test('rejects non-keyframe targets and round-trips the codec', () {
      final context = _TestContext(keyed().serialize());
      expect(
        SetKeyframeValueCommand(
          rawObjectIndex: 0,
          value: 1,
        ).execute(context).succeeded,
        isFalse,
      );
      final decoded =
          EditorCommandCodec.instance.decode(
                SetKeyframeValueCommand(rawObjectIndex: 7, value: 3.5).toJson(),
              )
              as SetKeyframeValueCommand;
      expect(decoded.rawObjectIndex, 7);
      expect(decoded.value, 3.5);
    });
  });
  group('SetKeyframeInterpolationCommand', () {
    RivRawDocument keyed() {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      RivAnimationFactory.insertKeyframe(
        raw,
        artboardOrdinal: 0,
        animationOrdinal: 0,
        objectId: 1,
        propertyKey: 13,
        frame: 5,
        value: 42,
      );
      return raw;
    }

    int keyframeIndex(RivRawDocument raw) {
      for (var i = 0; i < raw.objects.length; i++) {
        if (raw.objects[i].typeKey == RivTypeKeys.keyFrameDouble) return i;
      }
      return -1;
    }

    test('switches linear to hold with byte-identity undo', () {
      final context = _TestContext(keyed().serialize());
      final before = context.editor.raw.serialize();
      final index = keyframeIndex(context.editor.raw);
      final command = SetKeyframeInterpolationCommand(
        rawObjectIndex: index,
        interpolationType: 0,
      );
      expect(command.execute(context).succeeded, isTrue);
      final keyframe = RivParser.fromRaw(context.editor.raw)
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single
          .keyframes
          .single;
      expect(keyframe.interpolation, RivInterpolationType.hold);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);
    });

    test('no-ops when the type is unchanged', () {
      final context = _TestContext(keyed().serialize());
      final index = keyframeIndex(context.editor.raw);
      final result = SetKeyframeInterpolationCommand(
        rawObjectIndex: index,
        interpolationType: 1, // Already linear.
      ).execute(context);
      expect(result.succeeded, isFalse);
    });

    test('rejects non-keyframe targets and cubic types', () {
      final context = _TestContext(keyed().serialize());
      expect(
        SetKeyframeInterpolationCommand(
          rawObjectIndex: 0,
          interpolationType: 0,
        ).execute(context).succeeded,
        isFalse,
      );
      expect(
        () => SetKeyframeInterpolationCommand(
          rawObjectIndex: 5,
          interpolationType: 2,
        ),
        throwsAssertionError,
      );
    });

    test('round-trips through the codec', () {
      final decoded =
          EditorCommandCodec.instance.decode(
                SetKeyframeInterpolationCommand(
                  rawObjectIndex: 9,
                  interpolationType: 0,
                ).toJson(),
              )
              as SetKeyframeInterpolationCommand;
      expect(decoded.rawObjectIndex, 9);
      expect(decoded.interpolationType, 0);
    });
  });
  group('cubic interpolation', () {
    RivRawDocument keyed() {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      for (final (frame, value) in [(0, 0.0), (30, 100.0)]) {
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13,
          frame: frame,
          value: value,
        );
      }
      return raw;
    }

    int firstKeyframeIndex(RivRawDocument raw) {
      for (var i = 0; i < raw.objects.length; i++) {
        if (raw.objects[i].typeKey == RivTypeKeys.keyFrameDouble) return i;
      }
      return -1;
    }

    test('setKeyframeCubic appends an interpolator and links it', () {
      final raw = keyed();
      expect(
        RivAnimationFactory.setKeyframeCubic(
          raw,
          rawObjectIndex: firstKeyframeIndex(raw),
          x1: 0.42,
          y1: 0,
          x2: 0.58,
          y2: 1,
        ),
        isTrue,
      );
      final keyframe = RivParser.parse(raw.serialize())
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single
          .keyframes
          .first;
      expect(keyframe.interpolation, RivInterpolationType.cubic);
      expect(keyframe.cubic, isNotNull);
      expect(keyframe.cubic!.x1, closeTo(0.42, 1e-5));
      expect(keyframe.cubic!.y2, closeTo(1, 1e-5));
    });

    test('re-applying cubic reuses the existing interpolator', () {
      final raw = keyed();
      final index = firstKeyframeIndex(raw);
      RivAnimationFactory.setKeyframeCubic(
        raw,
        rawObjectIndex: index,
        x1: 0.42,
        y1: 0,
        x2: 0.58,
        y2: 1,
      );
      final countAfterFirst = raw.objects
          .where((o) => o.typeKey == RivTypeKeys.cubicEaseInterpolator)
          .length;
      RivAnimationFactory.setKeyframeCubic(
        raw,
        rawObjectIndex: index,
        x1: 0.1,
        y1: 0.2,
        x2: 0.3,
        y2: 0.4,
      );
      final countAfterSecond = raw.objects
          .where((o) => o.typeKey == RivTypeKeys.cubicEaseInterpolator)
          .length;
      expect(countAfterFirst, 1);
      expect(countAfterSecond, 1);
      final keyframe = RivParser.parse(raw.serialize())
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single
          .keyframes
          .first;
      expect(keyframe.cubic!.x1, closeTo(0.1, 1e-5));
    });

    test('does not shift existing component indices', () {
      final raw = keyed();
      final namesBefore = RivParser.fromRaw(
        raw,
      ).artboards.single.componentNames;
      RivAnimationFactory.setKeyframeCubic(
        raw,
        rawObjectIndex: firstKeyframeIndex(raw),
        x1: 0.42,
        y1: 0,
        x2: 0.58,
        y2: 1,
      );
      final namesAfter = RivParser.parse(
        raw.serialize(),
      ).artboards.single.componentNames;
      for (final entry in namesBefore.entries) {
        expect(namesAfter[entry.key], entry.value);
      }
    });

    test('SetKeyframeCubicCommand: byte-identity undo + merge + codec', () {
      final context = _TestContext(keyed().serialize());
      final before = context.editor.raw.serialize();
      final index = firstKeyframeIndex(context.editor.raw);

      final processor = CommandProcessor(context: context);
      processor.execute(
        SetKeyframeCubicCommand(
          rawObjectIndex: index,
          x1: 0.42,
          y1: 0,
          x2: 0.58,
          y2: 1,
        ),
      );
      processor.execute(
        SetKeyframeCubicCommand(
          rawObjectIndex: index,
          x1: 0.2,
          y1: 0.1,
          x2: 0.8,
          y2: 0.9,
        ),
      );
      // Merged: one undo restores the original bytes.
      processor.undo();
      expect(processor.canUndo, isFalse);
      expect(context.editor.raw.serialize(), before);

      final decoded =
          EditorCommandCodec.instance.decode(
                SetKeyframeCubicCommand(
                  rawObjectIndex: 3,
                  x1: 0.1,
                  y1: 0.2,
                  x2: 0.3,
                  y2: 0.4,
                ).toJson(),
              )
              as SetKeyframeCubicCommand;
      expect(decoded.x2, 0.3);
    });

    test('evaluator eases exactly through the bezier solver', () {
      const ease = RivCubicEase.easeInOut;
      // ease-in-out at x=0.5 is exactly 0.5 by symmetry.
      expect(
        RivKeyframeEvaluator.debugCubicEaseT(0.5, ease),
        closeTo(0.5, 1e-4),
      );
      // Early progress is slower than linear for ease-in-out.
      expect(RivKeyframeEvaluator.debugCubicEaseT(0.25, ease), lessThan(0.25));
      // Endpoints are exact.
      expect(RivKeyframeEvaluator.debugCubicEaseT(0, ease), 0);
      expect(RivKeyframeEvaluator.debugCubicEaseT(1, ease), 1);
    });
  });
  group('TransformKeyframesCommand', () {
    RivRawDocument keyed() {
      final raw = RivRawDocument.parse(_documentWithShape());
      RivAnimationFactory.addAnimation(raw, artboardOrdinal: 0, name: 'A');
      for (final (frame, value) in [(0, 0.0), (30, 100.0)]) {
        RivAnimationFactory.insertKeyframe(
          raw,
          artboardOrdinal: 0,
          animationOrdinal: 0,
          objectId: 1,
          propertyKey: 13,
          frame: frame,
          value: value,
        );
      }
      return raw;
    }

    List<int> keyframeIndices(RivRawDocument raw) => [
      for (var i = 0; i < raw.objects.length; i++)
        if (raw.objects[i].typeKey == RivTypeKeys.keyFrameDouble) i,
    ];

    test('moves a group atomically with byte-identity undo', () {
      final context = _TestContext(keyed().serialize());
      final before = context.editor.raw.serialize();
      final indices = keyframeIndices(context.editor.raw);
      final command = TransformKeyframesCommand(
        moves: [
          KeyframeMove(rawObjectIndex: indices[0], frame: 10, value: 5),
          KeyframeMove(rawObjectIndex: indices[1], frame: 40, value: 105),
        ],
      );
      expect(command.execute(context).succeeded, isTrue);
      final keyframes = RivParser.fromRaw(context.editor.raw)
          .artboards
          .single
          .animations
          .single
          .keyedObjects
          .single
          .properties
          .single
          .keyframes;
      expect(keyframes.map((k) => k.frame), [10, 40]);
      expect(keyframes.map((k) => k.value), [5, 105]);
      expect(command.undo(context).succeeded, isTrue);
      expect(context.editor.raw.serialize(), before);
    });

    test('rejects the batch when any target is not a keyframe', () {
      final context = _TestContext(keyed().serialize());
      final before = context.editor.raw.serialize();
      final indices = keyframeIndices(context.editor.raw);
      final result = TransformKeyframesCommand(
        moves: [
          KeyframeMove(rawObjectIndex: indices[0], frame: 5, value: 1),
          KeyframeMove(rawObjectIndex: 0, frame: 5, value: 1), // Backboard
        ],
      ).execute(context);
      expect(result.succeeded, isFalse);
      expect(
        context.editor.raw.serialize(),
        before,
        reason: 'atomic: a bad batch must not partially apply',
      );
    });

    test('merges continuous group drags into one entry', () {
      final context = _TestContext(keyed().serialize());
      final processor = CommandProcessor(context: context);
      final indices = keyframeIndices(context.editor.raw);
      for (final delta in [5, 10]) {
        processor.execute(
          TransformKeyframesCommand(
            moves: [
              KeyframeMove(rawObjectIndex: indices[0], frame: delta, value: 0),
              KeyframeMove(
                rawObjectIndex: indices[1],
                frame: 30 + delta,
                value: 100,
              ),
            ],
          ),
        );
      }
      processor.undo();
      expect(processor.canUndo, isFalse);
    });

    test('round-trips through the codec', () {
      final decoded =
          EditorCommandCodec.instance.decode(
                TransformKeyframesCommand(
                  moves: const [
                    KeyframeMove(rawObjectIndex: 4, frame: 12, value: 3.5),
                  ],
                ).toJson(),
              )
              as TransformKeyframesCommand;
      expect(decoded.moves.single.frame, 12);
      expect(decoded.moves.single.value, 3.5);
    });
  });
}
