/// Typed failure surfaced by command execution (§4.7: failures are
/// sealed classes, never bare strings).
sealed class CommandFailure {
  const CommandFailure();

  /// What happened, in user-facing language.
  String get message;
}

/// The document is missing or not editable.
final class DocumentUnavailableFailure extends CommandFailure {
  const DocumentUnavailableFailure();

  @override
  String get message => 'No editable document is open';
}

/// The command's target (component, keyframe, artboard) no longer exists.
final class TargetNotFoundFailure extends CommandFailure {
  const TargetNotFoundFailure(this.target);

  final String target;

  @override
  String get message => 'Target not found: $target';
}

/// The mutation was rejected by the document layer (e.g. reparenting a
/// node into its own subtree, or unhealable dangling references).
final class InvalidMutationFailure extends CommandFailure {
  const InvalidMutationFailure(this.reason);

  final String reason;

  @override
  String get message => reason;
}

/// The command would not change the document (treated as failure so
/// no-ops never pollute the undo history).
final class NoChangeFailure extends CommandFailure {
  const NoChangeFailure();

  @override
  String get message => 'Nothing to change';
}

/// Outcome of executing or undoing a command.
final class CommandResult {
  const CommandResult.success() : failure = null;
  const CommandResult.failed(CommandFailure this.failure);

  final CommandFailure? failure;

  bool get succeeded => failure == null;
}
