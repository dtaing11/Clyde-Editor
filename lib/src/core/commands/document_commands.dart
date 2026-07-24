import 'dart:typed_data';

import '../../riv/riv_artboard_editor.dart';
import '../../riv/riv_document_builder.dart';
import '../../riv/riv_document_model.dart';

import 'command_result.dart';
import 'editor_command.dart';

/// Base for commands whose undo restores the exact pre-execution bytes.
///
/// The snapshot is captured inside [execute], making `execute -> undo`
/// byte-identical by construction. Snapshots are runtime-only state:
/// [toJson] carries the command *parameters* so a serialised command can
/// be re-executed (macros, collaboration), not undone remotely.
abstract class SnapshotUndoCommand extends EditorCommand {
  SnapshotUndoCommand();

  Uint8List? _beforeBytes;

  /// Performs the mutation. The document is already snapshotted.
  CommandResult mutate(DocumentContext context);

  @override
  CommandResult execute(DocumentContext context) {
    final editor = context.editor;
    if (editor == null) {
      return const CommandResult.failed(DocumentUnavailableFailure());
    }
    final snapshot = editor.bytes();
    final result = mutate(context);
    if (result.succeeded) {
      _beforeBytes = snapshot;
      editor.rebuild();
    }
    return result;
  }

  @override
  CommandResult undo(DocumentContext context) {
    final editor = context.editor;
    final before = _beforeBytes;
    if (editor == null) {
      return const CommandResult.failed(DocumentUnavailableFailure());
    }
    if (before == null) {
      return const CommandResult.failed(
        InvalidMutationFailure('Command has not been executed'),
      );
    }
    editor.replaceBytes(before);
    return const CommandResult.success();
  }
}

/// Moves a keyframe to a new frame position.
final class RetimeKeyframeCommand extends SnapshotUndoCommand {
  RetimeKeyframeCommand({
    required this.rawObjectIndex,
    required this.newFrame,
    required this.durationFrames,
  });

  factory RetimeKeyframeCommand.fromJson(Map<String, dynamic> json) =>
      RetimeKeyframeCommand(
        rawObjectIndex: json['rawObjectIndex'] as int,
        newFrame: json['newFrame'] as int,
        durationFrames: json['durationFrames'] as int,
      );

  static const String type = 'retimeKeyframe';

  final int rawObjectIndex;
  final int newFrame;
  final int durationFrames;

  @override
  String get label => 'Move keyframe';

  @override
  bool get isMergeable => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final editor = context.editor!;
    final keyframe = _findKeyframe(editor.model);
    if (keyframe == null) {
      return CommandResult.failed(
        TargetNotFoundFailure('keyframe@$rawObjectIndex'),
      );
    }
    final changed = editor.retimeKeyframe(
      keyframe,
      newFrame,
      durationFrames: durationFrames,
    );
    return changed
        ? const CommandResult.success()
        : const CommandResult.failed(NoChangeFailure());
  }

  RivKeyFrameModel? _findKeyframe(RivDocumentModel model) {
    for (final artboard in model.artboards) {
      for (final animation in artboard.animations) {
        for (final keyedObject in animation.keyedObjects) {
          for (final property in keyedObject.properties) {
            for (final keyframe in property.keyframes) {
              if (keyframe.rawObjectIndex == rawObjectIndex) return keyframe;
            }
          }
        }
      }
    }
    return null;
  }

  @override
  EditorCommand? mergeWith(EditorCommand next) {
    if (next is! RetimeKeyframeCommand ||
        next.rawObjectIndex != rawObjectIndex) {
      return null;
    }
    // Keep this command's snapshot (the original state) and the newest
    // target frame, so one drag is one history entry.
    return RetimeKeyframeCommand(
      rawObjectIndex: rawObjectIndex,
      newFrame: next.newFrame,
      durationFrames: next.durationFrames,
    ).._beforeBytes = _beforeBytes;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rawObjectIndex': rawObjectIndex,
    'newFrame': newFrame,
    'durationFrames': durationFrames,
  };
}

/// Base for structural scene commands addressed by artboard + component.
abstract base class ComponentCommand extends SnapshotUndoCommand {
  ComponentCommand({
    required this.artboardOrdinal,
    required this.componentIndex,
  });

  final int artboardOrdinal;
  final int componentIndex;

  /// Runs the structural operation via the artboard editor.
  RivStructuralResult operate(RivArtboardEditor editor);

  /// Whether the operation shifts component indices.
  bool get shiftsIndices => true;

  @override
  CommandResult mutate(DocumentContext context) {
    final result = operate(
      RivArtboardEditor(context.editor!.raw, artboardOrdinal),
    );
    if (!result.succeeded) {
      return const CommandResult.failed(
        InvalidMutationFailure('The document rejected this change'),
      );
    }
    if (shiftsIndices) {
      context.reportComponentRemap(artboardOrdinal, result.remap);
    }
    return const CommandResult.success();
  }
}

/// Renames a scene component.
final class RenameComponentCommand extends ComponentCommand {
  RenameComponentCommand({
    required super.artboardOrdinal,
    required super.componentIndex,
    required this.newName,
  });

  factory RenameComponentCommand.fromJson(Map<String, dynamic> json) =>
      RenameComponentCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
        newName: json['newName'] as String,
      );

  static const String type = 'renameComponent';

  final String newName;

  @override
  String get label => 'Rename to "$newName"';

  @override
  bool get shiftsIndices => false;

  @override
  RivStructuralResult operate(RivArtboardEditor editor) =>
      editor.rename(componentIndex, newName)
      ? const RivStructuralResult.success({})
      : const RivStructuralResult.failure();

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
    'newName': newName,
  };
}

/// Sets or clears the runtime Hidden flag on a drawable component.
final class SetComponentHiddenCommand extends ComponentCommand {
  SetComponentHiddenCommand({
    required super.artboardOrdinal,
    required super.componentIndex,
    required this.hidden,
  });

  factory SetComponentHiddenCommand.fromJson(Map<String, dynamic> json) =>
      SetComponentHiddenCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
        hidden: json['hidden'] as bool,
      );

  static const String type = 'setComponentHidden';

  final bool hidden;

  @override
  String get label => hidden ? 'Hide' : 'Show';

  @override
  bool get shiftsIndices => false;

  @override
  RivStructuralResult operate(RivArtboardEditor editor) =>
      editor.setHidden(componentIndex, hidden)
      ? const RivStructuralResult.success({})
      : const RivStructuralResult.failure();

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
    'hidden': hidden,
  };
}

/// Moves a component (and subtree) under a new parent.
final class ReparentComponentCommand extends ComponentCommand {
  ReparentComponentCommand({
    required super.artboardOrdinal,
    required super.componentIndex,
    required this.newParentIndex,
    this.insertAfterSibling,
  });

  factory ReparentComponentCommand.fromJson(Map<String, dynamic> json) =>
      ReparentComponentCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
        newParentIndex: json['newParentIndex'] as int,
        insertAfterSibling: json['insertAfterSibling'] as int?,
      );

  static const String type = 'reparentComponent';

  final int newParentIndex;
  final int? insertAfterSibling;

  @override
  String get label => 'Move';

  @override
  RivStructuralResult operate(RivArtboardEditor editor) => editor.reparent(
    componentIndex,
    newParentIndex,
    insertAfterSibling: insertAfterSibling,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
    'newParentIndex': newParentIndex,
    'insertAfterSibling': insertAfterSibling,
  };
}

/// Duplicates a component subtree.
final class DuplicateComponentCommand extends ComponentCommand {
  DuplicateComponentCommand({
    required super.artboardOrdinal,
    required super.componentIndex,
  });

  factory DuplicateComponentCommand.fromJson(Map<String, dynamic> json) =>
      DuplicateComponentCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
      );

  static const String type = 'duplicateComponent';

  @override
  String get label => 'Duplicate';

  @override
  RivStructuralResult operate(RivArtboardEditor editor) =>
      editor.duplicate(componentIndex);

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
  };
}

/// Deletes a component subtree.
final class DeleteComponentCommand extends ComponentCommand {
  DeleteComponentCommand({
    required super.artboardOrdinal,
    required super.componentIndex,
  });

  factory DeleteComponentCommand.fromJson(Map<String, dynamic> json) =>
      DeleteComponentCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        componentIndex: json['componentIndex'] as int,
      );

  static const String type = 'deleteComponent';

  @override
  String get label => 'Delete';

  @override
  RivStructuralResult operate(RivArtboardEditor editor) =>
      editor.delete(componentIndex);

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'componentIndex': componentIndex,
  };
}

/// Appends a new artboard to the document.
final class AddArtboardCommand extends SnapshotUndoCommand {
  AddArtboardCommand({
    required this.name,
    this.width = defaultSize,
    this.height = defaultSize,
  });

  factory AddArtboardCommand.fromJson(Map<String, dynamic> json) =>
      AddArtboardCommand(
        name: json['name'] as String,
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  static const String type = 'addArtboard';
  static const double defaultSize = 500;

  final String name;
  final double width;
  final double height;

  @override
  String get label => 'Add artboard "$name"';

  @override
  CommandResult mutate(DocumentContext context) {
    RivDocumentBuilder.appendArtboard(
      context.editor!.raw,
      name: name,
      width: width,
      height: height,
    );
    return const CommandResult.success();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'width': width,
    'height': height,
  };
}

/// Embeds an image asset into the document.
final class ImportImageAssetCommand extends SnapshotUndoCommand {
  ImportImageAssetCommand({required this.name, required this.assetBytes});

  factory ImportImageAssetCommand.fromJson(Map<String, dynamic> json) =>
      ImportImageAssetCommand(
        name: json['name'] as String,
        assetBytes: Uint8List.fromList(
          (json['assetBytes'] as List).cast<int>(),
        ),
      );

  static const String type = 'importImageAsset';

  final String name;
  final Uint8List assetBytes;

  @override
  String get label => 'Import "$name"';

  @override
  CommandResult mutate(DocumentContext context) {
    final raw = context.editor!.raw;
    RivDocumentBuilder.embedImageAsset(
      raw,
      name: name,
      bytes: assetBytes,
      assetId: RivDocumentBuilder.nextAssetId(raw),
    );
    return const CommandResult.success();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'assetBytes': assetBytes.toList(),
  };
}
