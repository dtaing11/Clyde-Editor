import 'dart:convert';
import 'dart:typed_data';

import 'riv_document_model.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Builds the display model ([RivDocumentModel]) from a `.riv` binary.
///
/// Parsing happens in two stages:
/// 1. [RivRawDocument.parse] losslessly splits the byte stream into raw
///    objects (the editing substrate).
/// 2. This parser walks those raw objects, mirroring the import order of
///    `File::read` in rive-runtime, and produces the artboard/animation/
///    keyframe model used by the timeline and inspector.
///
/// Each keyframe records the index of its raw object so editors can map
/// display models back to bytes.
class RivParser {
  /// Parses [bytes] and returns the animation model, or throws
  /// [RivFormatException] when the buffer is not a valid `.riv` file.
  static RivDocumentModel parse(Uint8List bytes) {
    return fromRaw(RivRawDocument.parse(bytes));
  }

  /// Builds the display model from an already-parsed [raw] document.
  static RivDocumentModel fromRaw(RivRawDocument raw) {
    final artboards = <RivArtboardModel>[];
    _ParseContext? context;

    for (var index = 0; index < raw.objects.length; index++) {
      final object = raw.objects[index];
      switch (object.typeKey) {
        case RivTypeKeys.artboard:
          context = _ParseContext(
            RivArtboardModel(name: _name(object)),
          );
          artboards.add(context.artboard);
          // The artboard itself is object index 0 in its own object list.
          context.registerComponent(context.artboard.name);
        case RivTypeKeys.linearAnimation:
          context?.beginAnimation(_animation(object));
        case RivTypeKeys.keyedObject:
          context?.beginKeyedObject(
            _uint(object, RivPropertyKeys.keyedObjectId) ?? 0,
          );
        case RivTypeKeys.keyedProperty:
          context?.beginKeyedProperty(
            _uint(object, RivPropertyKeys.keyedPropertyKey) ?? 0,
          );
        case RivTypeKeys.keyFrameDouble:
          context?.addKeyFrame(_keyFrame(object, index, readValue: true));
        case RivTypeKeys.keyFrameColor:
        case RivTypeKeys.keyFrameId:
        case RivTypeKeys.keyFrameBool:
        case RivTypeKeys.keyFrameUint:
        case RivTypeKeys.keyFrameString:
          context?.addKeyFrame(_keyFrame(object, index, readValue: false));
        default:
          // Every artboard component occupies an object slot; keyed
          // objects address components by that index. Interpolators are
          // also imported as components by the runtime.
          if (context != null &&
              (!RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
                  RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey))) {
            context.registerComponent(_name(object));
          }
      }
    }

    for (final artboard in artboards) {
      for (final animation in artboard.animations) {
        for (final keyedObject in animation.keyedObjects) {
          final name = artboard.componentNames[keyedObject.objectId];
          if (name != null && name.isNotEmpty) {
            keyedObject.resolveName(name);
          }
        }
      }
    }

    return RivDocumentModel(
      majorVersion: raw.majorVersion,
      minorVersion: raw.minorVersion,
      artboards: artboards,
    );
  }

  static String _name(RivRawObject object) {
    final property = object.property(RivPropertyKeys.componentName);
    if (property == null || property.fieldType != RivFieldType.string) {
      return '';
    }
    // Value bytes are length-prefixed UTF-8.
    final raw = property.valueBytes;
    var length = 0;
    var shift = 0;
    var offset = 0;
    while (offset < raw.length) {
      final byte = raw[offset++];
      length |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return utf8.decode(
      raw.sublist(offset, offset + length),
      allowMalformed: true,
    );
  }

  static int? _uint(RivRawObject object, int key) {
    final property = object.property(key);
    if (property == null || property.fieldType != RivFieldType.uint) {
      return null;
    }
    return property.uintValue;
  }

  static double? _float(RivRawObject object, int key) {
    final property = object.property(key);
    if (property == null || property.fieldType != RivFieldType.float) {
      return null;
    }
    return property.floatValue;
  }

  static RivAnimationModel _animation(RivRawObject object) {
    return RivAnimationModel(
      name: _name(object),
      fps: _uint(object, RivPropertyKeys.animationFps) ?? 60,
      durationFrames: _uint(object, RivPropertyKeys.animationDuration) ?? 60,
    );
  }

  static RivKeyFrameModel _keyFrame(
    RivRawObject object,
    int rawObjectIndex, {
    required bool readValue,
  }) {
    return RivKeyFrameModel(
      frame: _uint(object, RivPropertyKeys.keyFrameFrame) ?? 0,
      interpolation: RivInterpolationType.fromId(
        _uint(object, RivPropertyKeys.keyFrameInterpolationType) ?? 1,
      ),
      value: readValue
          ? _float(object, RivPropertyKeys.keyFrameDoubleValue)
          : null,
      rawObjectIndex: rawObjectIndex,
    );
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
