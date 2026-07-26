import 'dart:typed_data';

import '../../riv/riv_format.dart';
import '../../riv/riv_hierarchy.dart';
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
    final object = RivHierarchy.componentObjectAt(
      context.editor!.raw,
      artboardOrdinal,
      componentIndex,
    );
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

/// Translates components to absolute node positions (canvas drags).
///
/// Carries every dragged component in one command so multi-selection
/// drags are one undo entry; mergeable so continuous pointer moves
/// coalesce into a single history item.
final class MoveComponentsCommand extends SnapshotUndoCommand {
  MoveComponentsCommand({required this.artboardOrdinal, required this.moves});

  factory MoveComponentsCommand.fromJson(Map<String, dynamic> json) =>
      MoveComponentsCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        moves: [
          for (final move in json['moves'] as List)
            ComponentMove(
              componentIndex: (move as Map)['componentIndex'] as int,
              x: (move['x'] as num).toDouble(),
              y: (move['y'] as num).toDouble(),
            ),
        ],
      );

  static const String type = 'moveComponents';

  final int artboardOrdinal;
  final List<ComponentMove> moves;

  @override
  String get label => moves.length == 1 ? 'Move' : 'Move ${moves.length} items';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final objects = RivHierarchy.componentObjects(
      context.editor!.raw,
      artboardOrdinal,
    );

    var changed = false;
    for (final move in moves) {
      final object = objects[move.componentIndex];
      if (object == null) {
        return CommandResult.failed(
          TargetNotFoundFailure(
            'component@$artboardOrdinal:${move.componentIndex}',
          ),
        );
      }
      changed =
          _setFloat(object, RivPropertyKeys.nodeX, move.x) | changed;
      changed =
          _setFloat(object, RivPropertyKeys.nodeY, move.y) | changed;
    }
    return changed
        ? const CommandResult.success()
        : const CommandResult.failed(NoChangeFailure());
  }

  static bool _setFloat(RivRawObject object, int key, double value) {
    final property = object.property(key);
    if (property != null) {
      if (property.fieldType != RivFieldType.float ||
          property.floatValue == value) {
        return false;
      }
      property.floatValue = value;
      return true;
    }
    object.properties.add(
      RivRawProperty(
        key: key,
        fieldType: RivFieldType.float,
        valueBytes: Uint8List(0),
      )..floatValue = value,
    );
    return true;
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! MoveComponentsCommand ||
        next.artboardOrdinal != artboardOrdinal ||
        next.moves.length != moves.length) {
      return null;
    }
    for (var i = 0; i < moves.length; i++) {
      if (next.moves[i].componentIndex != moves[i].componentIndex) return null;
    }
    // Keep this command's snapshot (drag start) and the newest positions.
    return MoveComponentsCommand(artboardOrdinal: artboardOrdinal, moves: next.moves)
      ..adoptSnapshotFrom(this);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'moves': [
      for (final move in moves)
        {'componentIndex': move.componentIndex, 'x': move.x, 'y': move.y},
    ],
  };
}

/// One component's target position within a [MoveComponentsCommand].
final class ComponentMove {
  const ComponentMove({
    required this.componentIndex,
    required this.x,
    required this.y,
  });

  final int componentIndex;
  final double x;
  final double y;
}
