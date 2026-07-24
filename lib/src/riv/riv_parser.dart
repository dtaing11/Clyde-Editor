import 'dart:typed_data';

import 'riv_binary_reader.dart';
import 'riv_document_model.dart';
import 'riv_format.dart';
import 'riv_property_table.g.dart';

/// Parses the animation data out of a `.riv` binary.
///
/// Follows the same algorithm as `File::read` in rive-runtime: read the
/// runtime header (with its property table of contents), then a flat
/// stream of objects, each a typeKey followed by (propertyKey, value)
/// pairs terminated by 0.
///
/// The parser is deliberately tolerant: objects and properties it does
/// not understand are skipped using the field-type table, exactly like
/// the C++ runtime does, so future format additions never break it.
class RivParser {
  RivParser._(this._reader);

  final RivBinaryReader _reader;

  /// Maps property keys to their field type as declared in the file's
  /// table of contents.
  final Map<int, RivFieldType> _propertyToc = {};

  /// Parses [bytes] and returns the animation model, or throws
  /// [RivFormatException] when the buffer is not a valid `.riv` file.
  static RivDocumentModel parse(Uint8List bytes) {
    return RivParser._(RivBinaryReader(bytes))._parse();
  }

  RivDocumentModel _parse() {
    final (major, minor) = _readHeader();

    final artboards = <RivArtboardModel>[];
    _ParseContext? context;

    while (!_reader.isAtEnd) {
      final typeKey = _reader.readVarUint();
      if (typeKey == 0) break;

      switch (typeKey) {
        case RivTypeKeys.artboard:
          context = _ParseContext(RivArtboardModel(name: _readName(typeKey)));
          artboards.add(context.artboard);
          // The artboard itself is object index 0 in its own object list.
          context.registerComponent(context.artboard.name);
        case RivTypeKeys.linearAnimation:
          context?.beginAnimation(_readLinearAnimation());
          if (context == null) _skipObject();
        case RivTypeKeys.keyedObject:
          final objectId = _readSingleUintProperty(
            RivPropertyKeys.keyedObjectId,
          );
          context?.beginKeyedObject(objectId);
        case RivTypeKeys.keyedProperty:
          final propertyKey = _readSingleUintProperty(
            RivPropertyKeys.keyedPropertyKey,
          );
          context?.beginKeyedProperty(propertyKey);
        case RivTypeKeys.keyFrameDouble:
          final keyframe = _readKeyFrame(readValue: true);
          context?.addKeyFrame(keyframe);
        case RivTypeKeys.keyFrameColor:
        case RivTypeKeys.keyFrameId:
        case RivTypeKeys.keyFrameBool:
        case RivTypeKeys.keyFrameUint:
        case RivTypeKeys.keyFrameString:
          final keyframe = _readKeyFrame(readValue: false);
          context?.addKeyFrame(keyframe);
        default:
          final consumedName = _skipObject(collectName: true);
          // Every artboard component occupies an object slot; keyed
          // objects address components by that index. Interpolators are
          // also imported as components by the runtime.
          if (context != null &&
              (!RivTypeKeys.animationTypeKeys.contains(typeKey) ||
                  RivTypeKeys.interpolatorTypeKeys.contains(typeKey))) {
            context.registerComponent(consumedName);
          }
      }
    }

    for (final artboard in artboards) {
      _resolveNames(artboard);
    }

    return RivDocumentModel(
      majorVersion: major,
      minorVersion: minor,
      artboards: artboards,
    );
  }

  (int, int) _readHeader() {
    const fingerprint = 'RIVE';
    for (var i = 0; i < fingerprint.length; i++) {
      if (_reader.readByte() != fingerprint.codeUnitAt(i)) {
        throw const RivFormatException('Not a RIVE file');
      }
    }
    final major = _reader.readVarUint();
    final minor = _reader.readVarUint();
    _reader.readVarUint(); // fileId, unused.

    final propertyKeys = <int>[];
    for (
      var key = _reader.readVarUint();
      key != 0;
      key = _reader.readVarUint()
    ) {
      propertyKeys.add(key);
    }
    var currentInt = 0;
    var currentBit = 8;
    for (final key in propertyKeys) {
      if (currentBit == 8) {
        currentInt = _reader.readUint32();
        currentBit = 0;
      }
      _propertyToc[key] = RivFieldType.fromId((currentInt >> currentBit) & 3);
      currentBit += 2;
    }
    return (major, minor);
  }

  /// Reads properties of the current object, returning its name property
  /// (if any) and skipping everything else.
  String _readName(int typeKey) {
    String name = '';
    _forEachProperty((propertyKey, fieldType) {
      if (propertyKey == RivPropertyKeys.componentName &&
          fieldType == RivFieldType.string) {
        name = _reader.readString();
        return true;
      }
      return false;
    });
    return name;
  }

  RivAnimationModel _readLinearAnimation() {
    var name = '';
    var fps = 60;
    var duration = 60;
    _forEachProperty((propertyKey, fieldType) {
      switch (propertyKey) {
        case RivPropertyKeys.animationName:
          name = _reader.readString();
          return true;
        case RivPropertyKeys.animationFps:
          fps = _reader.readVarUint();
          return true;
        case RivPropertyKeys.animationDuration:
          duration = _reader.readVarUint();
          return true;
      }
      return false;
    });
    return RivAnimationModel(name: name, fps: fps, durationFrames: duration);
  }

  int _readSingleUintProperty(int wantedKey) {
    var value = 0;
    _forEachProperty((propertyKey, fieldType) {
      if (propertyKey == wantedKey) {
        value = _reader.readVarUint();
        return true;
      }
      return false;
    });
    return value;
  }

  RivKeyFrameModel _readKeyFrame({required bool readValue}) {
    var frame = 0;
    var interpolation = RivInterpolationType.linear;
    double? value;
    _forEachProperty((propertyKey, fieldType) {
      switch (propertyKey) {
        case RivPropertyKeys.keyFrameFrame:
          frame = _reader.readVarUint();
          return true;
        case RivPropertyKeys.keyFrameInterpolationType:
          interpolation = RivInterpolationType.fromId(_reader.readVarUint());
          return true;
        case RivPropertyKeys.keyFrameDoubleValue when readValue:
          value = _reader.readFloat32();
          return true;
      }
      return false;
    });
    return RivKeyFrameModel(
      frame: frame,
      interpolation: interpolation,
      value: value,
    );
  }

  /// Skips an entire object's property list. When [collectName] is true,
  /// returns the component name if one was present.
  String _skipObject({bool collectName = false}) {
    var name = '';
    _forEachProperty((propertyKey, fieldType) {
      if (collectName &&
          propertyKey == RivPropertyKeys.componentName &&
          fieldType == RivFieldType.string) {
        name = _reader.readString();
        return true;
      }
      return false;
    });
    return name;
  }

  /// Iterates the (propertyKey, value) pairs of the current object.
  ///
  /// [handler] returns true when it consumed the value; otherwise the
  /// value is skipped based on the field type table.
  void _forEachProperty(
    bool Function(int propertyKey, RivFieldType? fieldType) handler,
  ) {
    while (true) {
      final propertyKey = _reader.readVarUint();
      if (propertyKey == 0) return;

      final fieldType = _fieldTypeOf(propertyKey);
      if (handler(propertyKey, fieldType)) continue;

      switch (fieldType) {
        case RivFieldType.uint:
          _reader.readVarUint();
        case RivFieldType.string:
          _reader.skipBytes();
        case RivFieldType.float:
          _reader.readFloat32();
        case RivFieldType.color:
          _reader.readUint32();
        case null:
          throw RivFormatException(
            'Unknown property key $propertyKey missing from ToC',
          );
      }
    }
  }

  RivFieldType? _fieldTypeOf(int propertyKey) {
    final coreId = rivCorePropertyFieldTypes[propertyKey];
    if (coreId != null) return RivFieldType.fromId(coreId);
    return _propertyToc[propertyKey];
  }

  void _resolveNames(RivArtboardModel artboard) {
    for (final animation in artboard.animations) {
      for (final keyedObject in animation.keyedObjects) {
        final name = artboard.componentNames[keyedObject.objectId];
        if (name != null && name.isNotEmpty) {
          // Rebuild with resolved name (records are immutable by design).
          keyedObject.resolveName(name);
        }
      }
    }
  }
}

/// Tracks the current artboard/animation/keyed-object/property while the
/// flat object stream is consumed.
class _ParseContext {
  _ParseContext(this.artboard);

  final RivArtboardModel artboard;
  int _componentIndex = 0;
  RivAnimationModel? _animation;
  RivKeyedObjectModel? _keyedObject;
  RivKeyedPropertyModel? _keyedProperty;

  void registerComponent(String name) {
    artboard.componentNames[_componentIndex] = name;
    _componentIndex++;
  }

  void beginAnimation(RivAnimationModel animation) {
    _animation = animation;
    _keyedObject = null;
    _keyedProperty = null;
    artboard.animations.add(animation);
  }

  void beginKeyedObject(int objectId) {
    final animation = _animation;
    if (animation == null) return;
    _keyedObject = RivKeyedObjectModel(
      objectId: objectId,
      objectName: 'Object $objectId',
    );
    _keyedProperty = null;
    animation.keyedObjects.add(_keyedObject!);
  }

  void beginKeyedProperty(int propertyKey) {
    final keyedObject = _keyedObject;
    if (keyedObject == null) return;
    _keyedProperty = RivKeyedPropertyModel(propertyKey: propertyKey);
    keyedObject.properties.add(_keyedProperty!);
  }

  void addKeyFrame(RivKeyFrameModel keyframe) {
    _keyedProperty?.keyframes.add(keyframe);
  }
}
