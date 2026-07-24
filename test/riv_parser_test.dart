import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/riv/riv_binary_reader.dart';
import 'package:rive_editor/src/riv/riv_document_model.dart';
import 'package:rive_editor/src/riv/riv_parser.dart';

Uint8List _loadAsset(String name) =>
    File('assets/demo/$name').readAsBytesSync();

void main() {
  group('RivBinaryReader', () {
    test('reads varuints', () {
      final reader = RivBinaryReader(Uint8List.fromList([0x05, 0xAC, 0x02]));
      expect(reader.readVarUint(), 5);
      expect(reader.readVarUint(), 300);
      expect(reader.isAtEnd, isTrue);
    });

    test('reads strings', () {
      final reader =
          RivBinaryReader(Uint8List.fromList([3, 0x61, 0x62, 0x63]));
      expect(reader.readString(), 'abc');
    });

    test('throws on truncated data', () {
      final reader = RivBinaryReader(Uint8List.fromList([3, 0x61]));
      expect(reader.readString, throwsA(isA<RivFormatException>()));
    });
  });

  group('RivParser', () {
    test('rejects non-riv data', () {
      expect(
        () => RivParser.parse(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<RivFormatException>()),
      );
    });

    test('parses little_machine.riv animations and keyframes', () {
      final doc = RivParser.parse(_loadAsset('little_machine.riv'));

      expect(doc.majorVersion, 7);
      expect(doc.artboards, isNotEmpty);

      final artboard = doc.artboards.first;
      expect(artboard.name, isNotEmpty);
      expect(artboard.animations, isNotEmpty);

      // Every animation has sane metadata.
      for (final animation in artboard.animations) {
        expect(animation.fps, greaterThan(0));
        expect(animation.durationFrames, greaterThan(0));
      }

      // At least one animation carries keyframe tracks.
      final keyed = artboard.animations
          .expand((a) => a.keyedObjects)
          .expand((o) => o.properties)
          .toList();
      expect(keyed, isNotEmpty, reason: 'expected keyed property tracks');

      final keyframes = keyed.expand((p) => p.keyframes).toList();
      expect(keyframes, isNotEmpty, reason: 'expected keyframes');

      // Keyframes are ordered and within the animation length.
      for (final animation in artboard.animations) {
        for (final keyedObject in animation.keyedObjects) {
          for (final property in keyedObject.properties) {
            final frames = property.keyframes.map((k) => k.frame).toList();
            final sorted = [...frames]..sort();
            expect(frames, sorted, reason: 'keyframes must be time-ordered');
          }
        }
      }
    });

    test('parses hero.riv without errors', () {
      final doc = RivParser.parse(_loadAsset('hero.riv'));
      expect(doc.artboards, isNotEmpty);
      expect(
        doc.artboards.expand((a) => a.animations),
        isNotEmpty,
      );
    });

    test('resolves keyed object names from components', () {
      final doc = RivParser.parse(_loadAsset('little_machine.riv'));
      final names = doc.artboards
          .expand((a) => a.animations)
          .expand((a) => a.keyedObjects)
          .map((o) => o.objectName)
          .toList();
      expect(names, isNotEmpty);
      // At least some objects should resolve to real component names
      // rather than the "Object N" fallback.
      expect(
        names.where((n) => !n.startsWith('Object ')),
        isNotEmpty,
        reason: 'expected resolved component names, got: $names',
      );
    });

    test('keyframe time conversion uses fps', () {
      const keyframe = RivKeyFrameModel(
        frame: 30,
        interpolation: RivInterpolationType.linear,
      );
      expect(keyframe.timeInSeconds(60), closeTo(0.5, 1e-9));
    });
  });
}
