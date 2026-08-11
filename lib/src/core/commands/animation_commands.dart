import '../../riv/riv_animation_factory.dart';

import 'command_result.dart';
import 'document_commands.dart';
import 'editor_command.dart';

/// Creates a new LinearAnimation on an artboard.
final class AddAnimationCommand extends SnapshotUndoCommand {
  AddAnimationCommand({
    required this.artboardOrdinal,
    required this.name,
    this.fps = defaultFps,
    this.durationFrames = defaultDurationFrames,
  });

  factory AddAnimationCommand.fromJson(Map<String, dynamic> json) =>
      AddAnimationCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        name: json['name'] as String,
        fps: json['fps'] as int,
        durationFrames: json['durationFrames'] as int,
      );

  static const String type = 'addAnimation';
  static const int defaultFps = 60;
  static const int defaultDurationFrames = 60;

  final int artboardOrdinal;
  final String name;
  final int fps;
  final int durationFrames;

  @override
  String get label => 'Add animation "$name"';

  @override
  CommandResult mutate(DocumentContext context) {
    final ok = RivAnimationFactory.addAnimation(
      context.editor!.raw,
      artboardOrdinal: artboardOrdinal,
      name: name,
      fps: fps,
      durationFrames: durationFrames,
    );
    return ok
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure('artboard@$artboardOrdinal'),
          );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'name': name,
    'fps': fps,
    'durationFrames': durationFrames,
  };
}

/// Sets a double keyframe for one component property at a frame.
///
/// Mergeable per (animation, object, property, frame) so dragging a
/// value while keying coalesces into one history entry.
final class InsertKeyframeCommand extends SnapshotUndoCommand {
  InsertKeyframeCommand({
    required this.artboardOrdinal,
    required this.animationOrdinal,
    required this.objectId,
    required this.propertyKey,
    required this.frame,
    required this.value,
  });

  factory InsertKeyframeCommand.fromJson(Map<String, dynamic> json) =>
      InsertKeyframeCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        animationOrdinal: json['animationOrdinal'] as int,
        objectId: json['objectId'] as int,
        propertyKey: json['propertyKey'] as int,
        frame: json['frame'] as int,
        value: (json['value'] as num).toDouble(),
      );

  static const String type = 'insertKeyframe';

  final int artboardOrdinal;
  final int animationOrdinal;
  final int objectId;
  final int propertyKey;
  final int frame;
  final double value;

  @override
  String get label => 'Set keyframe';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final ok = RivAnimationFactory.insertKeyframe(
      context.editor!.raw,
      artboardOrdinal: artboardOrdinal,
      animationOrdinal: animationOrdinal,
      objectId: objectId,
      propertyKey: propertyKey,
      frame: frame,
      value: value,
    );
    return ok
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure(
              'animation@$artboardOrdinal:$animationOrdinal',
            ),
          );
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! InsertKeyframeCommand ||
        next.artboardOrdinal != artboardOrdinal ||
        next.animationOrdinal != animationOrdinal ||
        next.objectId != objectId ||
        next.propertyKey != propertyKey ||
        next.frame != frame) {
      return null;
    }
    return InsertKeyframeCommand(
      artboardOrdinal: artboardOrdinal,
      animationOrdinal: animationOrdinal,
      objectId: objectId,
      propertyKey: propertyKey,
      frame: frame,
      value: next.value,
    )..adoptSnapshotFrom(this);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'animationOrdinal': animationOrdinal,
    'objectId': objectId,
    'propertyKey': propertyKey,
    'frame': frame,
    'value': value,
  };
}

/// Deletes a keyframe by its raw object index, pruning empty keyed
/// containers.
final class DeleteKeyframeCommand extends SnapshotUndoCommand {
  DeleteKeyframeCommand({required this.rawObjectIndex});

  factory DeleteKeyframeCommand.fromJson(Map<String, dynamic> json) =>
      DeleteKeyframeCommand(rawObjectIndex: json['rawObjectIndex'] as int);

  static const String type = 'deleteKeyframe';

  final int rawObjectIndex;

  @override
  String get label => 'Delete keyframe';

  @override
  CommandResult mutate(DocumentContext context) {
    final ok = RivAnimationFactory.deleteKeyframe(
      context.editor!.raw,
      rawObjectIndex,
    );
    return ok
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure('keyframe@$rawObjectIndex'),
          );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rawObjectIndex': rawObjectIndex,
  };
}

/// Sets a uint property (loop mode, fps, duration) on an animation.
final class SetAnimationUintCommand extends SnapshotUndoCommand {
  SetAnimationUintCommand({
    required this.artboardOrdinal,
    required this.animationOrdinal,
    required this.propertyKey,
    required this.value,
    this.commandLabel = 'Edit animation',
  });

  factory SetAnimationUintCommand.fromJson(Map<String, dynamic> json) =>
      SetAnimationUintCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        animationOrdinal: json['animationOrdinal'] as int,
        propertyKey: json['propertyKey'] as int,
        value: json['value'] as int,
      );

  static const String type = 'setAnimationUint';

  final int artboardOrdinal;
  final int animationOrdinal;
  final int propertyKey;
  final int value;
  final String commandLabel;

  @override
  String get label => commandLabel;

  @override
  CommandResult mutate(DocumentContext context) {
    final ok = RivAnimationFactory.setAnimationUint(
      context.editor!.raw,
      artboardOrdinal: artboardOrdinal,
      animationOrdinal: animationOrdinal,
      propertyKey: propertyKey,
      value: value,
    );
    return ok
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure(
              'animation@$artboardOrdinal:$animationOrdinal',
            ),
          );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'animationOrdinal': animationOrdinal,
    'propertyKey': propertyKey,
    'value': value,
  };
}
