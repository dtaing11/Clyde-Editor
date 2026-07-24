import '../../riv/riv_document_editor.dart';

import 'command_result.dart';

/// The document surface commands mutate.
///
/// Commands receive this instead of reaching into editor state, keeping
/// the application layer free of Flutter and of panel concerns (§4.2).
abstract interface class DocumentContext {
  /// The editable document, or `null` when none is open.
  RivDocumentEditor? get editor;

  /// Index remaps produced by structural edits, reported so selection
  /// and UI state keyed by component index can migrate (old -> new,
  /// -1 for removed). Keyed by artboard ordinal.
  void reportComponentRemap(int artboardOrdinal, Map<int, int> remap);
}

/// A single, undoable, serialisable document mutation (§4.4).
///
/// Implementations must be deterministic: no wall-clock reads, no
/// randomness. `execute` followed by `undo` must return the document to
/// a byte-identical state, which is enforced by tests for every
/// command type.
abstract class EditorCommand {
  const EditorCommand();

  /// Shown in the undo menu and command history.
  String get label;

  /// Whether consecutive commands of the same type on the same target
  /// may be merged into one history entry (e.g. drag operations).
  bool get isMergeable => false;

  CommandResult execute(DocumentContext context);

  CommandResult undo(DocumentContext context);

  /// Serialised form, required from day one for macros and
  /// collaboration (§4.4). `type` identifies the command in
  /// [EditorCommandCodec].
  Map<String, dynamic> toJson();

  /// Attempts to merge [next] into this command, returning the merged
  /// command or `null` when merging is not possible.
  EditorCommand? mergeWith(EditorCommand next) => null;
}
