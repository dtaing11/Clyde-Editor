import 'dart:typed_data';

/// Sequential writer for the Rive binary (`.riv`) encoding.
///
/// Counterpart of [RivBinaryReader]; mirrors `rive::BinaryWriter` in
/// rive-runtime: little-endian scalars, LEB128 variable-length unsigned
/// integers, and length-prefixed byte blobs.
class RivBinaryWriter {
  final BytesBuilder _builder = BytesBuilder();

  int get length => _builder.length;

  /// Writes a single byte.
  void writeByte(int value) {
    assert(value >= 0 && value <= 0xFF);
    _builder.addByte(value);
  }

  /// Writes a variable-length unsigned integer (LEB128, minimal form).
  void writeVarUint(int value) {
    assert(value >= 0);
    var remaining = value;
    do {
      var byte = remaining & 0x7F;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      _builder.addByte(byte);
    } while (remaining != 0);
  }

  /// Writes a 32-bit little-endian float.
  void writeFloat32(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes a 32-bit little-endian unsigned integer.
  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes a length-prefixed byte blob (strings, embedded assets).
  void writeBytes(Uint8List bytes) {
    writeVarUint(bytes.length);
    _builder.add(bytes);
  }

  /// Writes raw bytes without a length prefix.
  void writeRaw(Uint8List bytes) => _builder.add(bytes);

  Uint8List takeBytes() => _builder.takeBytes();
}
