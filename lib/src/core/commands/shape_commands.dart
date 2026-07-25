import 'dart:typed_data';

import '../../riv/riv_shape_factory.dart';

import 'command_result.dart';
import 'document_commands.dart';
import 'editor_command.dart';

/// Creates a parametric shape (rectangle/ellipse) in an artboard.
final class AddShapeCommand extends SnapshotUndoCommand {
  AddShapeCommand({
    required this.artboardOrdinal,
    required this.kind,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.color = defaultColor,
  });

  factory AddShapeCommand.fromJson(Map<String, dynamic> json) =>
      AddShapeCommand(
        artboardOrdinal: json['artboardOrdinal'] as int,
        kind: RivShapeKind.values.byName(json['kind'] as String),
        name: json['name'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        color: json['color'] as int,
      );

  static const String type = 'addShape';

  /// Opaque blue-ish default fill (ARGB), matching the editor accent.
  static const int defaultColor = 0xFF57A5FF;

  final int artboardOrdinal;
  final RivShapeKind kind;
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final int color;

  @override
  String get label => 'Add ${kind.name}';

  @override
  CommandResult mutate(DocumentContext context) {
    final added = RivShapeFactory.addShape(
      context.editor!.raw,
      artboardOrdinal: artboardOrdinal,
      kind: kind,
      name: name,
      x: x,
      y: y,
      width: width,
      height: height,
      color: color,
    );
    return added
        ? const CommandResult.success()
        : CommandResult.failed(
            TargetNotFoundFailure('artboard@$artboardOrdinal'),
          );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'artboardOrdinal': artboardOrdinal,
    'kind': kind.name,
    'name': name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'color': color,
  };
}

/// Creates a text object with an embedded font in an artboard.
final class AddTextCommand extends SnapshotUndoCommand {
  AddTextCommand({
    required this.artboardOrdinal,
    required this.name,
    required this.text,
    required this.x,
    required this.y,
    required this.fontBytes,
    required this.fontName,
    this.fontSize = defaultFontSize,
    this.color = defaultColor,
  });

  factory AddTextCommand.fromJson(Map<String, dynamic> json) => AddTextCommand(
    artboardOrdinal: json['artboardOrdinal'] as int,
    name: json['name'] as String,
    text: json['text'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    fontSize: (json['fontSize'] as num).toDouble(),
    color: json['color'] as int,
    fontBytes: Uint8List.fromList((json['fontBytes'] as List).cast<int>()),
    fontName: json['fontName'] as String,
  );

  static const String type = 'addText';
  static const double defaultFontSize = 32;
  static const int defaultColor = 0xFFEDEDED;

  final int artboardOrdinal;
  final String name;
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int color;
  final Uint8List fontBytes;
  final String fontName;

  @override
  String get label => 'Add text';

  @override
  CommandResult mutate(DocumentContext context) {
    final added = RivShapeFactory.addText(
      context.editor!.raw,
      artboardOrdinal: artboardOrdinal,
      name: name,
      text: text,
      x: x,
      y: y,
      fontSize: fontSize,
      color: color,
      fontBytes: fontBytes,
      fontName: fontName,
    );
    return added
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
    'text': text,
    'x': x,
    'y': y,
    'fontSize': fontSize,
    'color': color,
    'fontBytes': fontBytes.toList(),
    'fontName': fontName,
  };
}
