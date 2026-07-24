import 'dart:typed_data';

import 'riv_binary_writer.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Creates new `.riv` content: blank documents, artboards, and embedded
/// assets.
///
/// Produces byte streams matching the runtime format version 7.0 with an
/// empty property table of contents (all properties we write are core
/// properties known to every runtime).
abstract final class RivDocumentBuilder {
  /// Runtime format version written to new files (`rive::File`).
  static const int majorVersion = 7;
  static const int minorVersion = 0;

  /// Builds a blank document: a backboard plus one artboard.
  static Uint8List newDocument({
    String artboardName = 'Artboard',
    double width = 500,
    double height = 500,
  }) {
    final writer = RivBinaryWriter();
    _writeHeader(writer);

    // Backboard: the file-level root object.
    writer.writeVarUint(RivTypeKeys.backboard);
    writer.writeVarUint(0);

    _writeArtboard(writer, artboardName, width, height);
    return writer.takeBytes();
  }

  /// Appends a new artboard to [document].
  ///
  /// Artboards are top-level objects; appending at the end of the stream
  /// keeps all existing artboard object spans intact.
  static void appendArtboard(
    RivRawDocument document, {
    required String name,
    double width = 500,
    double height = 500,
  }) {
    final writer = RivBinaryWriter();
    _writeArtboard(writer, name, width, height);
    final objects = RivRawDocument.parse(
      _withHeader(writer.takeBytes()),
    ).objects;
    document.objects.addAll(objects);
  }

  /// Embeds an image asset (PNG/JPEG/WebP bytes) into [document].
  ///
  /// The asset pair (FileAsset + FileAssetContents) is inserted directly
  /// after the backboard so it is registered before any artboard needs
  /// it, mirroring where the Rive exporter places assets.
  static void embedImageAsset(
    RivRawDocument document, {
    required String name,
    required Uint8List bytes,
    required int assetId,
  }) {
    final asset = RivRawObject(
      typeKey: RivTypeKeys.imageAsset,
      properties: [
        _stringProperty(RivPropertyKeys.assetName, name),
        _uintProperty(RivPropertyKeys.assetId, assetId),
      ],
    );
    final contents = RivRawObject(
      typeKey: RivTypeKeys.fileAssetContents,
      properties: [_bytesProperty(RivPropertyKeys.assetBytes, bytes)],
    );

    final backboardIndex = document.objects.indexWhere(
      (o) => o.typeKey == RivTypeKeys.backboard,
    );
    final insertAt = backboardIndex >= 0 ? backboardIndex + 1 : 0;
    document.objects.insertAll(insertAt, [asset, contents]);
  }

  /// Next unused asset id in [document].
  static int nextAssetId(RivRawDocument document) {
    var maxId = -1;
    for (final object in document.objects) {
      final property = object.property(RivPropertyKeys.assetId);
      if (property != null && property.fieldType == RivFieldType.uint) {
        final id = property.uintValue;
        if (id > maxId) maxId = id;
      }
    }
    return maxId + 1;
  }

  // -- Encoding helpers ----------------------------------------------------

  static void _writeHeader(RivBinaryWriter writer) {
    for (final byte in 'RIVE'.codeUnits) {
      writer.writeByte(byte);
    }
    writer.writeVarUint(majorVersion);
    writer.writeVarUint(minorVersion);
    writer.writeVarUint(0); // fileId
    writer.writeVarUint(0); // Empty property ToC.
  }

  static Uint8List _withHeader(Uint8List objectBytes) {
    final writer = RivBinaryWriter();
    _writeHeader(writer);
    writer.writeRaw(objectBytes);
    return writer.takeBytes();
  }

  static void _writeArtboard(
    RivBinaryWriter writer,
    String name,
    double width,
    double height,
  ) {
    writer.writeVarUint(RivTypeKeys.artboard);
    writer.writeVarUint(RivPropertyKeys.componentName);
    writer.writeBytes(Uint8List.fromList(name.codeUnits));
    writer.writeVarUint(RivPropertyKeys.layoutWidth);
    writer.writeFloat32(width);
    writer.writeVarUint(RivPropertyKeys.layoutHeight);
    writer.writeFloat32(height);
    writer.writeVarUint(0);
  }

  static RivRawProperty _stringProperty(int key, String value) {
    final writer = RivBinaryWriter()
      ..writeBytes(Uint8List.fromList(value.codeUnits));
    return RivRawProperty(
      key: key,
      fieldType: RivFieldType.string,
      valueBytes: writer.takeBytes(),
    );
  }

  static RivRawProperty _bytesProperty(int key, Uint8List value) {
    final writer = RivBinaryWriter()..writeBytes(value);
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
}
