import 'dart:typed_data';

import '../../riv/riv_animation_factory.dart';
import '../../riv/riv_binary_writer.dart';
import '../../riv/riv_format.dart';
import '../../riv/riv_raw_document.dart';

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

/// Sets a double keyframe's value (curve editor vertical drags).
///
/// Mergeable per keyframe so a continuous drag is one undo entry.
final class SetKeyframeValueCommand extends SnapshotUndoCommand {
  SetKeyframeValueCommand({required this.rawObjectIndex, required this.value});

  factory SetKeyframeValueCommand.fromJson(Map<String, dynamic> json) =>
      SetKeyframeValueCommand(
        rawObjectIndex: json['rawObjectIndex'] as int,
        value: (json['value'] as num).toDouble(),
      );

  static const String type = 'setKeyframeValue';

  final int rawObjectIndex;
  final double value;

  @override
  String get label => 'Edit keyframe value';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final raw = context.editor!.raw;
    if (rawObjectIndex < 0 || rawObjectIndex >= raw.objects.length) {
      return CommandResult.failed(
        TargetNotFoundFailure('keyframe@$rawObjectIndex'),
      );
    }
    final object = raw.objects[rawObjectIndex];
    if (object.typeKey != RivTypeKeys.keyFrameDouble) {
      return const CommandResult.failed(
        InvalidMutationFailure('Not a double keyframe'),
      );
    }
    final property = object.property(RivPropertyKeys.keyFrameDoubleValue);
    if (property == null) {
      object.properties.add(
        RivRawProperty(
          key: RivPropertyKeys.keyFrameDoubleValue,
          fieldType: RivFieldType.float,
          valueBytes: Uint8List(0),
        )..floatValue = value,
      );
      return const CommandResult.success();
    }
    if (property.floatValue == value) {
      return const CommandResult.failed(NoChangeFailure());
    }
    property.floatValue = value;
    return const CommandResult.success();
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! SetKeyframeValueCommand ||
        next.rawObjectIndex != rawObjectIndex) {
      return null;
    }
    return SetKeyframeValueCommand(
      rawObjectIndex: rawObjectIndex,
      value: next.value,
    )..adoptSnapshotFrom(this);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rawObjectIndex': rawObjectIndex,
    'value': value,
  };
}

/// Sets a keyframe's interpolation type (hold or linear).
///
/// Cubic interpolation requires interpolator objects and is handled by
/// the curve editor's tangent tooling later; this command intentionally
/// accepts only interpolator-free types.
final class SetKeyframeInterpolationCommand extends SnapshotUndoCommand {
  SetKeyframeInterpolationCommand({
    required this.rawObjectIndex,
    required this.interpolationType,
  }) : assert(
         interpolationType == 0 || interpolationType == 1,
         'Only hold (0) and linear (1) are interpolator-free',
       );

  factory SetKeyframeInterpolationCommand.fromJson(Map<String, dynamic> json) =>
      SetKeyframeInterpolationCommand(
        rawObjectIndex: json['rawObjectIndex'] as int,
        interpolationType: json['interpolationType'] as int,
      );

  static const String type = 'setKeyframeInterpolation';

  final int rawObjectIndex;

  /// 0 = hold, 1 = linear (`rive::KeyFrameInterpolation`).
  final int interpolationType;

  @override
  String get label =>
      interpolationType == 0 ? 'Set hold interpolation' : 'Set linear';

  @override
  CommandResult mutate(DocumentContext context) {
    final raw = context.editor!.raw;
    if (rawObjectIndex < 0 || rawObjectIndex >= raw.objects.length) {
      return CommandResult.failed(
        TargetNotFoundFailure('keyframe@$rawObjectIndex'),
      );
    }
    final object = raw.objects[rawObjectIndex];
    if (!RivTypeKeys.keyFrameTypeKeys.contains(object.typeKey)) {
      return const CommandResult.failed(
        InvalidMutationFailure('Not a keyframe'),
      );
    }
    final property = object.property(RivPropertyKeys.keyFrameInterpolationType);
    if (property != null) {
      if (property.uintValue == interpolationType) {
        return const CommandResult.failed(NoChangeFailure());
      }
      property.uintValue = interpolationType;
    } else {
      final writer = RivBinaryWriter()..writeVarUint(interpolationType);
      object.properties.add(
        RivRawProperty(
          key: RivPropertyKeys.keyFrameInterpolationType,
          fieldType: RivFieldType.uint,
          valueBytes: writer.takeBytes(),
        ),
      );
    }
    return const CommandResult.success();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rawObjectIndex': rawObjectIndex,
    'interpolationType': interpolationType,
  };
}

/// Makes a keyframe cubic with bezier ease control points.
///
/// Mergeable per keyframe so dragging ease handles coalesces into one
/// undo entry.
final class SetKeyframeCubicCommand extends SnapshotUndoCommand {
  SetKeyframeCubicCommand({
    required this.rawObjectIndex,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory SetKeyframeCubicCommand.fromJson(Map<String, dynamic> json) =>
      SetKeyframeCubicCommand(
        rawObjectIndex: json['rawObjectIndex'] as int,
        x1: (json['x1'] as num).toDouble(),
        y1: (json['y1'] as num).toDouble(),
        x2: (json['x2'] as num).toDouble(),
        y2: (json['y2'] as num).toDouble(),
      );

  static const String type = 'setKeyframeCubic';

  final int rawObjectIndex;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  @override
  String get label => 'Set cubic ease';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final ok = RivAnimationFactory.setKeyframeCubic(
      context.editor!.raw,
      rawObjectIndex: rawObjectIndex,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
    );
    return ok
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure('keyframe@$rawObjectIndex'),
          );
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! SetKeyframeCubicCommand ||
        next.rawObjectIndex != rawObjectIndex) {
      return null;
    }
    return SetKeyframeCubicCommand(
      rawObjectIndex: rawObjectIndex,
      x1: next.x1,
      y1: next.y1,
      x2: next.x2,
      y2: next.y2,
    )..adoptSnapshotFrom(this);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rawObjectIndex': rawObjectIndex,
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
  };
}
