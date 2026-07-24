import 'dart:convert';
import 'dart:typed_data';

/// Sequential reader for the Rive binary (`.riv`) encoding.
///
/// Mirrors `rive::BinaryReader` from rive-runtime: little-endian scalars,
/// LEB128-style variable-length unsigned integers and length-prefixed
/// UTF-8 strings.
class RivBinaryReader {
  RivBinaryReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _position = 0;

  int get position => _position;
  bool get isAtEnd => _position >= _bytes.length;
  int get remaining => _bytes.length - _position;

  /// Reads a single byte.
  int readByte() {
    _checkAvailable(1);
    return _bytes[_position++];
  }

  /// Reads a variable-length unsigned integer (LEB128).
  int readVarUint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readByte();
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) {
        throw const RivFormatException('VarUint overflow');
      }
    }
    return result;
  }

  /// Reads a 32-bit little-endian float.
  double readFloat32() {
    _checkAvailable(4);
    final value = _data.getFloat32(_position, Endian.little);
    _position += 4;
    return value;
  }

  /// Reads a 32-bit little-endian unsigned integer.
  int readUint32() {
    _checkAvailable(4);
    final value = _data.getUint32(_position, Endian.little);
    _position += 4;
    return value;
  }

  /// Reads a length-prefixed UTF-8 string.
  String readString() {
    final length = readVarUint();
    _checkAvailable(length);
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _position, _position + length),
      allowMalformed: true,
    );
    _position += length;
    return value;
  }

  /// Skips a length-prefixed byte blob (strings, embedded assets).
  void skipBytes() {
    final length = readVarUint();
    _checkAvailable(length);
    _position += length;
  }

  void _checkAvailable(int count) {
    if (_position + count > _bytes.length) {
      throw const RivFormatException('Unexpected end of file');
    }
  }
}

/// Thrown when a `.riv` buffer does not match the expected binary format.
class RivFormatException implements Exception {
  const RivFormatException(this.message);

  final String message;

  @override
  String toString() => 'RivFormatException: $message';
}
