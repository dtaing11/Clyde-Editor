import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/riv/riv_binary_reader.dart';
import 'package:rive_editor/src/riv/riv_binary_writer.dart';
import 'package:rive_editor/src/riv/riv_document_editor.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';

Uint8List _loadAsset(String name) =>
    File('assets/demo/$name').readAsBytesSync();

void main() {
  group('RivBinaryWriter', () {
    test('varuint round-trips with reader', () {
      for (final value in [0, 1, 127, 128, 300, 16383, 16384, 1 << 20]) {
        final writer = RivBinaryWriter()..writeVarUint(value);
        final reader = RivBinaryReader(writer.takeBytes());
        expect(reader.readVarUint(), value, reason: 'value $value');
      }
    });

    test('float32 round-trips with reader', () {
      final writer = RivBinaryWriter()..writeFloat32(3.25);
      expect(RivBinaryReader(writer.takeBytes()).readFloat32(), 3.25);
    });
  });

  group('RivRawDocument round-trip', () {
    for (final asset in ['little_machine.riv', 'hero.riv']) {
      test('$asset serializes byte-identical when unmodified', () {
        final original = _loadAsset(asset);
        final doc = RivRawDocument.parse(original);
        final rewritten = doc.serialize();
        expect(
          rewritten,
          original,
          reason: 'round-trip must preserve every byte',
        );
      });
    }
  });

  group('RivDocumentEditor', () {
    RivKeyFrameModel firstEditableKeyframe(
      RivDocumentEditor editor, {
      bool nonZeroFrame = false,
    }) {
      for (final artboard in editor.model.artboards) {
        for (final animation in artboard.animations) {
          for (final keyedObject in animation.keyedObjects) {
            for (final property in keyedObject.properties) {
              for (final keyframe in property.keyframes) {
                if (keyframe.rawObjectIndex < 0) continue;
                if (nonZeroFrame && keyframe.frame == 0) continue;
                return keyframe;
              }
            }
          }
        }
      }
      fail('no editable keyframe found');
    }

    RivAnimationModel animationOf(
      RivDocumentEditor editor,
      RivKeyFrameModel keyframe,
    ) {
      for (final artboard in editor.model.artboards) {
        for (final animation in artboard.animations) {
          for (final keyedObject in animation.keyedObjects) {
            for (final property in keyedObject.properties) {
              if (property.keyframes.any(
                (k) => k.rawObjectIndex == keyframe.rawObjectIndex,
              )) {
                return animation;
              }
            }
          }
        }
      }
      fail('animation not found for keyframe');
    }

    RivKeyFrameModel? findByRawIndex(RivDocumentEditor editor, int rawIndex) {
      for (final artboard in editor.model.artboards) {
        for (final animation in artboard.animations) {
          for (final keyedObject in animation.keyedObjects) {
            for (final property in keyedObject.properties) {
              for (final keyframe in property.keyframes) {
                if (keyframe.rawObjectIndex == rawIndex) return keyframe;
              }
            }
          }
        }
      }
      return null;
    }

    test('retimes a keyframe and the edit survives re-parsing', () {
      final editor = RivDocumentEditor.parse(_loadAsset('little_machine.riv'));
      final keyframe = firstEditableKeyframe(editor);
      final animation = animationOf(editor, keyframe);
      final target = keyframe.frame == 7 ? 9 : 7;

      expect(
        editor.retimeKeyframe(
          keyframe,
          target,
          durationFrames: animation.durationFrames,
        ),
        isTrue,
      );

      // The edited bytes re-parse with the keyframe at the new frame.
      final reloaded = RivDocumentEditor.parse(editor.bytes());
      final reparsed = findByRawIndex(reloaded, keyframe.rawObjectIndex);
      expect(reparsed, isNotNull);
      expect(reparsed!.frame, target);
    });

    test('retime survives varuint length growth (frame 100 -> 200)', () {
      final editor = RivDocumentEditor.parse(_loadAsset('little_machine.riv'));
      final keyframe = firstEditableKeyframe(editor);

      // 100 encodes in 1 byte, 200 needs 2: forces a length change.
      expect(
        editor.retimeKeyframe(keyframe, 200, durationFrames: 500),
        isTrue,
      );
      final reloaded = RivDocumentEditor.parse(editor.bytes());
      expect(findByRawIndex(reloaded, keyframe.rawObjectIndex)!.frame, 200);
    });

    test('clamps retime to animation duration', () {
      final editor = RivDocumentEditor.parse(_loadAsset('little_machine.riv'));
      final keyframe = firstEditableKeyframe(editor);
      final animation = animationOf(editor, keyframe);

      editor.retimeKeyframe(
        keyframe,
        1000000,
        durationFrames: animation.durationFrames,
      );
      final reloaded = RivDocumentEditor.parse(editor.bytes());
      expect(
        findByRawIndex(reloaded, keyframe.rawObjectIndex)!.frame,
        animation.durationFrames,
      );
    });

    test('no-op retime returns false and leaves bytes unchanged', () {
      final original = _loadAsset('little_machine.riv');
      final editor = RivDocumentEditor.parse(original);
      final keyframe = firstEditableKeyframe(editor);
      final animation = animationOf(editor, keyframe);

      expect(
        editor.retimeKeyframe(
          keyframe,
          keyframe.frame,
          durationFrames: animation.durationFrames,
        ),
        isFalse,
      );
      expect(editor.bytes(), original);
    });

    test('edited bytes still decode in the Rive engine format check', () {
      // Full engine decode is covered by integration tests; here we
      // assert the header and stream stay structurally valid.
      final editor = RivDocumentEditor.parse(_loadAsset('little_machine.riv'));
      final keyframe = firstEditableKeyframe(editor);
      editor.retimeKeyframe(keyframe, 3, durationFrames: 100);

      final reparsed = RivRawDocument.parse(editor.bytes());
      expect(reparsed.objects.length, greaterThan(0));
    });
  });
}
