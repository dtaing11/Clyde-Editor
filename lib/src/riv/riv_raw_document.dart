import 'dart:typed_data';

import 'riv_binary_reader.dart';
import 'riv_binary_writer.dart';
import 'riv_format.dart';
import 'riv_property_table.g.dart';

/// Lossless, editable representation of a `.riv` file.
///
/// The file is split into a raw header block and a flat list of
/// [RivRawObject]s. Property *values are kept as their original bytes*,
/// so serializing an unmodified document reproduces the input
/// byte-for-byte, even if the original encoder used non-minimal varuints.
/// Edits replace just the bytes of the touched property.
///
/// This is the editing substrate: display models (`RivDocumentModel`)
/// reference raw objects by index, and editors mutate them through
/// typed setters before calling [serialize].
class RivRawDocument {
  RivRawDocument._({
    required Uint8List headerBytes,
    required this.objects,
    required this.propertyToc,
    required this.majorVersion,
    required this.minorVersion,
    required bool hasTrailingTerminator,
  }) : _headerBytes = headerBytes,
       _hasTrailingTerminator = hasTrailingTerminator;

  /// The RIVE header including version, file id and property ToC,
  /// preserved verbatim.
  final Uint8List _headerBytes;

  /// All objects in stream order.
  final List<RivRawObject> objects;

  /// Field types declared in the file's table of contents.
  final Map<int, RivFieldType> propertyToc;

  /// Whether the original stream ended with a 0 type key terminator.
  final bool _hasTrailingTerminator;

  /// Runtime format version from the header.
  final int majorVersion;
  final int minorVersion;

  /// Parses [bytes] into an editable document.
  ///
  /// Throws [RivFormatException] for non-riv input.
  static RivRawDocument parse(Uint8List bytes) {
    final reader = RivBinaryReader(bytes);

    const fingerprint = 'RIVE';
    for (var i = 0; i < fingerprint.length; i++) {
      if (reader.readByte() != fingerprint.codeUnitAt(i)) {
        throw const RivFormatException('Not a RIVE file');
      }
    }
    final major = reader.readVarUint();
    final minor = reader.readVarUint();
    reader.readVarUint(); // fileId

    final propertyKeys = <int>[];
    for (var key = reader.readVarUint(); key != 0; key = reader.readVarUint()) {
      propertyKeys.add(key);
    }
    final toc = <int, RivFieldType>{};
    var currentInt = 0;
    var currentBit = 8;
    for (final key in propertyKeys) {
      if (currentBit == 8) {
        currentInt = reader.readUint32();
        currentBit = 0;
      }
      toc[key] = RivFieldType.fromId((currentInt >> currentBit) & 3);
      currentBit += 2;
    }

    final headerBytes = Uint8List.sublistView(bytes, 0, reader.position);

    RivFieldType? fieldTypeOf(int propertyKey) {
      final coreId = rivCorePropertyFieldTypes[propertyKey];
      if (coreId != null) return RivFieldType.fromId(coreId);
      return toc[propertyKey];
    }

    final objects = <RivRawObject>[];
    var hasTrailingTerminator = false;
    while (!reader.isAtEnd) {
      final typeKey = reader.readVarUint();
      if (typeKey == 0 && reader.isAtEnd) {
        hasTrailingTerminator = true;
        break;
      }
      final properties = <RivRawProperty>[];
      while (true) {
        final propertyKey = reader.readVarUint();
        if (propertyKey == 0) break;

        final fieldType = fieldTypeOf(propertyKey);
        if (fieldType == null) {
          throw RivFormatException(
            'Unknown property key $propertyKey missing from ToC',
          );
        }
        final start = reader.position;
        switch (fieldType) {
          case RivFieldType.uint:
            reader.readVarUint();
          case RivFieldType.string:
            reader.skipBytes();
          case RivFieldType.float:
            reader.readFloat32();
          case RivFieldType.color:
            reader.readUint32();
        }
        properties.add(
          RivRawProperty(
            key: propertyKey,
            fieldType: fieldType,
            valueBytes: Uint8List.sublistView(bytes, start, reader.position),
          ),
        );
      }
      objects.add(RivRawObject(typeKey: typeKey, properties: properties));
    }

    return RivRawDocument._(
      headerBytes: headerBytes,
      objects: objects,
      propertyToc: toc,
      majorVersion: major,
      minorVersion: minor,
      hasTrailingTerminator: hasTrailingTerminator,
    );
  }

  /// Serializes the document back to `.riv` bytes.
  Uint8List serialize() {
    final writer = RivBinaryWriter()..writeRaw(_headerBytes);
    for (final object in objects) {
      writer.writeVarUint(object.typeKey);
      for (final property in object.properties) {
        writer.writeVarUint(property.key);
        writer.writeRaw(property.valueBytes);
      }
      writer.writeVarUint(0); // Property terminator.
    }
    if (_hasTrailingTerminator) writer.writeVarUint(0);
    return writer.takeBytes();
  }
}

/// One object in the `.riv` stream: a type key plus its properties.
class RivRawObject {
  RivRawObject({required this.typeKey, required this.properties});

  final int typeKey;
  final List<RivRawProperty> properties;

  /// The property with [key], or `null`.
  RivRawProperty? property(int key) {
    for (final property in properties) {
      if (property.key == key) return property;
    }
    return null;
  }
}

/// One serialized property: key, declared field type, and value bytes.
///
/// Value bytes are preserved verbatim until edited through the typed
/// setters, which re-encode minimally.
class RivRawProperty {
  RivRawProperty({
    required this.key,
    required this.fieldType,
    required this.valueBytes,
  });

  final int key;
  final RivFieldType fieldType;
  Uint8List valueBytes;

  /// Decodes the value as a varuint. Only valid for [RivFieldType.uint].
  int get uintValue {
    assert(fieldType == RivFieldType.uint);
    return RivBinaryReader(valueBytes).readVarUint();
  }

  /// Re-encodes the value as a minimal varuint.
  set uintValue(int value) {
    assert(fieldType == RivFieldType.uint);
    final writer = RivBinaryWriter()..writeVarUint(value);
    valueBytes = writer.takeBytes();
  }

  /// Decodes the value as a float32. Only valid for [RivFieldType.float].
  double get floatValue {
    assert(fieldType == RivFieldType.float);
    return RivBinaryReader(valueBytes).readFloat32();
  }

  set floatValue(double value) {
    assert(fieldType == RivFieldType.float);
    final writer = RivBinaryWriter()..writeFloat32(value);
    valueBytes = writer.takeBytes();
  }
}
