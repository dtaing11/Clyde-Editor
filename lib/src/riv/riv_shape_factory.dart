import 'dart:typed_data';

import 'riv_binary_writer.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Kinds of parametric shapes the factory can build.
enum RivShapeKind {
  rectangle(RivTypeKeys.rectangle),
  ellipse(RivTypeKeys.ellipse);

  const RivShapeKind(this.pathTypeKey);

  /// Type key of the parametric path object for this kind.
  final int pathTypeKey;
}

/// Builds shape object recipes inside an artboard's object stream.
///
/// A visible shape in the runtime is a small tree, mirrored from what
/// the Rive exporter writes:
///
/// ```
/// Shape (typeKey 3)         parent: artboard (or any container)
///  ├── Rectangle/Ellipse    parent: shape (the parametric path)
///  └── Fill (typeKey 20)    parent: shape
///       └── SolidColor      parent: fill
/// ```
///
/// Objects are appended to the end of the artboard's span; parentId
/// values use the artboard's component index space.
abstract final class RivShapeFactory {
  /// Appends a [kind] shape to artboard [artboardOrdinal] of [document].
  ///
  /// [x]/[y] position the shape's node; [width]/[height] size the
  /// parametric path; [color] is ARGB. Returns `true` on success
  /// (fails only when the artboard does not exist).
  static bool addShape(
    RivRawDocument document, {
    required int artboardOrdinal,
    required RivShapeKind kind,
    required String name,
    required double x,
    required double y,
    required double width,
    required double height,
    required int color,
  }) {
    final span = _artboardSpan(document, artboardOrdinal);
    if (span == null) return false;

    final shapeIndex = span.componentCount;
    final shape = RivRawObject(
      typeKey: RivTypeKeys.shape,
      properties: [
        _stringProperty(RivPropertyKeys.componentName, name),
        _uintProperty(RivPropertyKeys.componentParentId, 0),
        _floatProperty(RivPropertyKeys.nodeX, x),
        _floatProperty(RivPropertyKeys.nodeY, y),
      ],
    );
    final path = RivRawObject(
      typeKey: kind.pathTypeKey,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, shapeIndex),
        _floatProperty(RivPropertyKeys.layoutWidth, width),
        _floatProperty(RivPropertyKeys.layoutHeight, height),
      ],
    );
    final fill = RivRawObject(
      typeKey: RivTypeKeys.fill,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, shapeIndex),
      ],
    );
    final solidColor = RivRawObject(
      typeKey: RivTypeKeys.solidColor,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, shapeIndex + 2),
        _colorProperty(RivPropertyKeys.solidColorValue, color),
      ],
    );

    document.objects.insertAll(span.endRawIndex, [
      shape,
      path,
      fill,
      solidColor,
    ]);
    return true;
  }

  // -- Span discovery ------------------------------------------------------

  /// Raw insertion point and component count of an artboard.
  static ({int endRawIndex, int componentCount})? _artboardSpan(
    RivRawDocument document,
    int artboardOrdinal,
  ) {
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

      var end = i + 1;
      var components = 1; // The artboard itself is component 0.
      while (end < document.objects.length &&
          !topLevelTypes.contains(document.objects[end].typeKey)) {
        final typeKey = document.objects[end].typeKey;
        final isComponent =
            !RivTypeKeys.animationTypeKeys.contains(typeKey) ||
            RivTypeKeys.interpolatorTypeKeys.contains(typeKey);
        if (isComponent) components++;
        end++;
      }
      return (endRawIndex: end, componentCount: components);
    }
    return null;
  }

  // -- Property encoding ---------------------------------------------------

  static RivRawProperty _stringProperty(int key, String value) {
    final writer = RivBinaryWriter()
      ..writeBytes(Uint8List.fromList(value.codeUnits));
    return RivRawProperty(
      key: key,
      fieldType: RivFieldType.string,
      valueBytes: writer.takeBytes(),
    );
  }

  static RivRawProperty _uintProperty(int key, int value) {
    final writer = RivBinaryWriter()..writeVarUint(value);
    return RivRawProperty(
      key: key,
      fieldType: RivFieldType.uint,
      valueBytes: writer.takeBytes(),
    );
  }

  static RivRawProperty _floatProperty(int key, double value) {
    final writer = RivBinaryWriter()..writeFloat32(value);
    return RivRawProperty(
      key: key,
      fieldType: RivFieldType.float,
      valueBytes: writer.takeBytes(),
    );
  }

  static RivRawProperty _colorProperty(int key, int value) {
    final writer = RivBinaryWriter()..writeUint32(value);
    return RivRawProperty(
      key: key,
      fieldType: RivFieldType.color,
      valueBytes: writer.takeBytes(),
    );
  }
}
