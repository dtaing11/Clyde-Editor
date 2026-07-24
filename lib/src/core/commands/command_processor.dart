import 'command_result.dart';
import 'editor_command.dart';

/// Executes commands against a [DocumentContext] and owns the undo/redo
/// history (§4.4: the spine of the application).
///
/// - Only successful commands enter the history.
/// - Mergeable commands coalesce with the previous entry so one drag is
///   one undo step.
/// - History depth is bounded so long sessions do not grow unboundedly.
final class CommandProcessor {
  CommandProcessor({required DocumentContext context, this.maxDepth = 100})
    : _context = context;

  final DocumentContext _context;
  final int maxDepth;

  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Label of the command that [undo] would revert, for menu display.
  String? get undoLabel => _undoStack.lastOrNull?.label;
  String? get redoLabel => _redoStack.lastOrNull?.label;

  /// Serialised history, oldest first (macro recording, diagnostics).
  List<Map<String, dynamic>> get historyJson => [
    for (final command in _undoStack) command.toJson(),
  ];

  CommandResult execute(EditorCommand command) {
    final result = command.execute(_context);
    if (!result.succeeded) return result;

    _redoStack.clear();

    final previous = _undoStack.lastOrNull;
    if (previous != null && previous.isMergeable && command.isMergeable) {
      final merged = previous.mergeWith(command);
      if (merged != null) {
        _undoStack[_undoStack.length - 1] = merged;
        return result;
      }
    }

    _undoStack.add(command);
    if (_undoStack.length > maxDepth) _undoStack.removeAt(0);
    return result;
  }

  CommandResult undo() {
    final command = _undoStack.lastOrNull;
    if (command == null) {
      return const CommandResult.failed(NoChangeFailure());
    }
    final result = command.undo(_context);
    if (result.succeeded) {
      _undoStack.removeLast();
      _redoStack.add(command);
    }
    return result;
  }

  CommandResult redo() {
    final command = _redoStack.lastOrNull;
    if (command == null) {
      return const CommandResult.failed(NoChangeFailure());
    }
    final result = command.execute(_context);
    if (result.succeeded) {
      _redoStack.removeLast();
      _undoStack.add(command);
    }
    return result;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
