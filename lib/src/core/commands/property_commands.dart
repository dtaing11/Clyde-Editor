import 'dart:typed_data';

import '../../riv/riv_format.dart';
import '../../riv/riv_raw_document.dart';

import 'command_result.dart';
import 'document_commands.dart';
import 'editor_command.dart';

/// Sets a float property on a component (inspector numeric edits).
///
/// Mergeable so dragging a numeric field coalesces into one undo entry
/// (§2.5 acceptance).
final class SetComponentPropertyCommand extends SnapshotUndoCommand {
  SetComponentPropertyCommand({
    required this.artboardOrdinal,
    required this.componentIndex,
    required this.propertyKey,
    required this.value,
  });

  factory SetComponentPropertyCommand.fromJson(Map<String, dynamic> json) =>
      SetComponentPropertyCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
        propertyKey: json['propertyKey'] as int,
        value: (json['value'] as num).toDouble(),
      );

  static const String type = 'setComponentProperty';

  final int artboardOrdinal;
  final int componentIndex;
  final int propertyKey;
  final double value;

  @override
  String get label => 'Edit property';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final object = _componentObject(context.editor!.raw);
    if (object == null) {
      return CommandResult.failed(
        TargetNotFoundFailure('component@$artboardOrdinal:$componentIndex'),
      );
    }

    final property = object.property(propertyKey);
    if (property != null) {
      if (property.fieldType != RivFieldType.float) {
        return const CommandResult.failed(
          InvalidMutationFailure('Property is not numeric'),
        );
      }
      if (property.floatValue == value) {
        return const CommandResult.failed(NoChangeFailure());
      }
      property.floatValue = value;
    } else {
      object.properties.add(
        RivRawProperty(
          key: propertyKey,
          fieldType: RivFieldType.float,
          valueBytes: Uint8List(0),
        )..floatValue = value,
      );
    }
    return const CommandResult.success();
  }

  RivRawObject? _componentObject(RivRawDocument document) {
    const topLevelTypes = {
      RivTypeKeys.artboard,
      RivTypeKeys.backboard,
      RivTypeKeys.imageAsset,
      RivTypeKeys.fontAsset,
      RivTypeKeys.audioAsset,
      RivTypeKeys.fileAssetContents,
    };

    var seen = -1;
    for (var i = 0; i < document.objects.length; i++) {
      if (document.objects[i].typeKey != RivTypeKeys.artboard) continue;
      seen++;
      if (seen != artboardOrdinal) continue;

      var component = 0;
      if (componentIndex == 0) return document.objects[i];
      for (var j = i + 1; j < document.objects.length; j++) {
        final object = document.objects[j];
        if (topLevelTypes.contains(object.typeKey)) break;
        final isComponent =
            !RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
            RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey);
        if (!isComponent) continue;
        component++;
        if (component == componentIndex) return object;
      }
      break;
    }
    return null;
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! SetComponentPropertyCommand ||
        next.artboardOrdinal != artboardOrdinal ||
        next.componentIndex != componentIndex ||
        next.propertyKey != propertyKey) {
      return null;
    }
    return SetComponentPropertyCommand(
      artboardOrdinal: artboardOrdinal,
      componentIndex: componentIndex,
      propertyKey: propertyKey,
      value: next.value,
    )..adoptSnapshotFrom(this);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
    'propertyKey': propertyKey,
    'value': value,
  };
}
