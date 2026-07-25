import 'dart:typed_data';

import 'riv_binary_writer.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Kinds of parametric shapes the factory can build.
enum RivShapeKind {
  rectangle(RivTypeKeys.rectangle),
  ellipse(RivTypeKeys.ellipse),
  polygon(RivTypeKeys.polygon);

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
  /// parametric path; [color] is ARGB. [polygonPoints] applies to
  /// [RivShapeKind.polygon] only. Returns `true` on success (fails only
  /// when the artboard does not exist).
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
    int polygonPoints = defaultPolygonPoints,
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
        if (kind == RivShapeKind.polygon)
          _uintProperty(RivPropertyKeys.polygonPoints, polygonPoints),
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

  /// Default vertex count for new polygons (matches the Rive editor).
  static const int defaultPolygonPoints = 5;

  /// Appends a text object with an embedded font to [document].
  ///
  /// The runtime text tree is:
  ///
  /// ```
  /// Text (typeKey 134)         parent: artboard, node x/y + width
  ///  ├── TextStylePaint (137)  parent: text, fontSize + fontAssetId
  ///  │    └── Fill → SolidColor
  ///  └── TextValueRun (135)    parent: text, styleId → the style
  /// ```
  ///
  /// The style's `fontAssetId` indexes the file's asset list; the font
  /// bytes are embedded as FontAsset + FileAssetContents before the
  /// first artboard so every artboard can reference them.
  static bool addText(
    RivRawDocument document, {
    required int artboardOrdinal,
    required String name,
    required String text,
    required double x,
    required double y,
    required double fontSize,
    required int color,
    required Uint8List fontBytes,
    required String fontName,
  }) {
    final span = _artboardSpan(document, artboardOrdinal);
    if (span == null) return false;

    final fontAssetId = _ensureFontAsset(document, fontName, fontBytes);

    final textIndex = span.componentCount;
    final styleIndex = textIndex + 1;
    final textObject = RivRawObject(
      typeKey: RivTypeKeys.text,
      properties: [
        _stringProperty(RivPropertyKeys.componentName, name),
        _uintProperty(RivPropertyKeys.componentParentId, 0),
        _floatProperty(RivPropertyKeys.nodeX, x),
        _floatProperty(RivPropertyKeys.nodeY, y),
      ],
    );
    final style = RivRawObject(
      typeKey: RivTypeKeys.textStylePaint,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, textIndex),
        _floatProperty(RivPropertyKeys.textStyleFontSize, fontSize),
        _uintProperty(RivPropertyKeys.textStyleFontAssetId, fontAssetId),
      ],
    );
    final fill = RivRawObject(
      typeKey: RivTypeKeys.fill,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, styleIndex),
      ],
    );
    final solidColor = RivRawObject(
      typeKey: RivTypeKeys.solidColor,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, styleIndex + 1),
        _colorProperty(RivPropertyKeys.solidColorValue, color),
      ],
    );
    final run = RivRawObject(
      typeKey: RivTypeKeys.textValueRun,
      properties: [
        _uintProperty(RivPropertyKeys.componentParentId, textIndex),
        _uintProperty(RivPropertyKeys.textRunStyleId, styleIndex),
        _stringProperty(RivPropertyKeys.textRunText, text),
      ],
    );

    // Re-resolve the span: embedding the font may have shifted indices
    // when the asset was inserted before this artboard.
    final freshSpan = _artboardSpan(document, artboardOrdinal)!;
    document.objects.insertAll(freshSpan.endRawIndex, [
      textObject,
      style,
      fill,
      solidColor,
      run,
    ]);
    return true;
  }

  /// Returns the asset id of a font named [fontName], embedding
  /// [fontBytes] as FontAsset + FileAssetContents when absent.
  static int _ensureFontAsset(
    RivRawDocument document,
    String fontName,
    Uint8List fontBytes,
  ) {
    var maxAssetId = -1;
    for (final object in document.objects) {
      if (object.typeKey != RivTypeKeys.fontAsset) continue;
      final idProperty = object.property(RivPropertyKeys.assetId);
      final nameProperty = object.property(RivPropertyKeys.assetName);
      final id = idProperty != null && idProperty.fieldType == RivFieldType.uint
          ? idProperty.uintValue
          : -1;
      if (id > maxAssetId) maxAssetId = id;
      if (nameProperty != null &&
          _decodeString(nameProperty.valueBytes) == fontName) {
        return id;
      }
    }

    final assetId = maxAssetId + 1;
    final asset = RivRawObject(
      typeKey: RivTypeKeys.fontAsset,
      properties: [
        _stringProperty(RivPropertyKeys.assetName, fontName),
        _uintProperty(RivPropertyKeys.assetId, assetId),
      ],
    );
    final contents = RivRawObject(
      typeKey: RivTypeKeys.fileAssetContents,
      properties: [
        RivRawProperty(
          key: RivPropertyKeys.assetBytes,
          fieldType: RivFieldType.string,
          valueBytes: (RivBinaryWriter()..writeBytes(fontBytes)).takeBytes(),
        ),
      ],
    );

    final backboardIndex = document.objects.indexWhere(
      (o) => o.typeKey == RivTypeKeys.backboard,
    );
    document.objects.insertAll(backboardIndex >= 0 ? backboardIndex + 1 : 0, [
      asset,
      contents,
    ]);
    return assetId;
  }

  static String _decodeString(Uint8List lengthPrefixed) {
    var length = 0;
    var shift = 0;
    var offset = 0;
    while (offset < lengthPrefixed.length) {
      final byte = lengthPrefixed[offset++];
      length |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return String.fromCharCodes(
      lengthPrefixed.sublist(offset, offset + length),
    );
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
