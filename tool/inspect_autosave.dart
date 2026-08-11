// ignore_for_file: avoid_print

import 'dart:io';
import 'package:rive_editor/src/riv/riv_parser.dart';

void main() {
  final bytes = File(
    '${Platform.environment['HOME']}/Library/Containers/dev.dinataing.riveEditor/Data/.clyde_editor/autosave/untitled.autosave.riv',
  ).readAsBytesSync();
  final model = RivParser.parse(bytes);
  for (final artboard in model.artboards) {
    print('artboard: ${artboard.name}');
    for (final animation in artboard.animations) {
      print(
        '  animation: ${animation.name} fps=${animation.fps} '
        'duration=${animation.durationFrames} loop=${animation.loop}',
      );
      for (final keyed in animation.keyedObjects) {
        print('    object ${keyed.objectId} (${keyed.objectName})');
        for (final property in keyed.properties) {
          for (final k in property.keyframes) {
            print(
              '      key ${property.propertyKey} frame=${k.frame} '
              'value=${k.value}',
            );
          }
        }
      }
    }
  }
}
