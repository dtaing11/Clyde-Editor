import 'editor_command.dart';
import 'document_commands.dart';
import 'property_commands.dart';
import 'shape_commands.dart';

/// Deserialises commands by type name (§4.5: a registry, not a switch).
///
/// Command types register a factory once; anything unregistered fails
/// loudly rather than silently dropping data.
final class EditorCommandCodec {
  EditorCommandCodec._();

  static final EditorCommandCodec instance = EditorCommandCodec._()
    .._registerBuiltIns();

  final Map<String, EditorCommand Function(Map<String, dynamic>)> _factories =
      {};

  void register(
    String type,
    EditorCommand Function(Map<String, dynamic>) factory,
  ) {
    assert(!_factories.containsKey(type), 'Duplicate command type: $type');
    _factories[type] = factory;
  }

  /// Recreates a command from its serialised form.
  ///
  /// Throws [ArgumentError] for unknown types: an unknown command in a
  /// macro or collaboration stream is a version mismatch that must
  /// surface, not vanish.
  EditorCommand decode(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final factory = type == null ? null : _factories[type];
    if (factory == null) {
      throw ArgumentError('Unknown command type: $type');
    }
    return factory(json);
  }

  void _registerBuiltIns() {
    register(RetimeKeyframeCommand.type, RetimeKeyframeCommand.fromJson);
    register(RenameComponentCommand.type, RenameComponentCommand.fromJson);
    register(
      SetComponentHiddenCommand.type,
      SetComponentHiddenCommand.fromJson,
    );
    register(ReparentComponentCommand.type, ReparentComponentCommand.fromJson);
    register(
      DuplicateComponentCommand.type,
      DuplicateComponentCommand.fromJson,
    );
    register(DeleteComponentCommand.type, DeleteComponentCommand.fromJson);
    register(AddArtboardCommand.type, AddArtboardCommand.fromJson);
    register(ImportImageAssetCommand.type, ImportImageAssetCommand.fromJson);
    register(AddShapeCommand.type, AddShapeCommand.fromJson);
    register(AddTextCommand.type, AddTextCommand.fromJson);
    register(
      SetComponentPropertyCommand.type,
      SetComponentPropertyCommand.fromJson,
    );
    register(MoveComponentsCommand.type, MoveComponentsCommand.fromJson);
    register(SetComponentColorCommand.type, SetComponentColorCommand.fromJson);
  }
}
