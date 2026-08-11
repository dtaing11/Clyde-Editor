import 'dart:typed_data';

import 'riv_binary_writer.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Creates and edits animation objects (LinearAnimation, KeyedObject,
/// KeyedProperty, KeyFrameDouble) in the raw `.riv` stream.
///
/// Stream layout mirrors the exporter: a LinearAnimation is followed by
/// its KeyedObjects, each followed by its KeyedProperties, each followed
/// by its KeyFrames, all inside the owning artboard's span. Animation
/// objects (except interpolators) do not consume component indices, so
/// inserting them never shifts component ids.
abstract final class RivAnimationFactory {
  /// Interpolation type written for new keyframes (1 = linear, matching
  /// the runtime's `KeyFrameInterpolation::linear`).
  static const int linearInterpolation = 1;

  /// Loop value for new animations (1 = loop).
  static const int loopValue = 1;

  /// Appends a [name] LinearAnimation to artboard [artboardOrdinal].
  ///
  /// Returns `true` on success (fails only when the artboard does not
  /// exist).
  static bool addAnimation(
    RivRawDocument document, {
    required int artboardOrdinal,
    required String name,
    int fps = 60,
    int durationFrames = 60,
  }) {
    final span = _artboardSpan(document, artboardOrdinal);
    if (span == null) return false;

    final animation = RivRawObject(
      typeKey: RivTypeKeys.linearAnimation,
      properties: [
        _stringProperty(RivPropertyKeys.animationName, name),
        _uintProperty(RivPropertyKeys.animationFps, fps),
        _uintProperty(RivPropertyKeys.animationDuration, durationFrames),
        _uintProperty(RivPropertyKeys.animationLoop, loopValue),
      ],
    );
    document.objects.insert(span.endRawIndex, animation);
    return true;
  }

  /// Sets or inserts a double keyframe for component [objectId]'s
  /// [propertyKey] at [frame] in animation [animationOrdinal] of
  /// artboard [artboardOrdinal].
  ///
  /// Reuses the existing KeyedObject/KeyedProperty when present and
  /// keeps keyframes in ascending frame order (the runtime's binary
  /// search requires it). An existing keyframe at [frame] has its value
  /// replaced. Returns `true` on success.
  static bool insertKeyframe(
    RivRawDocument document, {
    required int artboardOrdinal,
    required int animationOrdinal,
    required int objectId,
    required int propertyKey,
    required int frame,
    required double value,
  }) {
    final span = _artboardSpan(document, artboardOrdinal);
    if (span == null) return false;

    final animation = _animationSpan(document, span, animationOrdinal);
    if (animation == null) return false;

    // Locate (or create) the KeyedObject for objectId.
    var keyedObjectStart = -1;
    var keyedObjectEnd = animation.end;
    for (var i = animation.start + 1; i < animation.end; i++) {
      final object = document.objects[i];
      if (object.typeKey != RivTypeKeys.keyedObject) continue;
      final id = object.property(RivPropertyKeys.keyedObjectId);
      if (keyedObjectStart >= 0) {
        keyedObjectEnd = i;
        break;
      }
      if (id != null && id.uintValue == objectId) keyedObjectStart = i;
    }

    if (keyedObjectStart < 0) {
      final insertAt = animation.end;
      document.objects.insertAll(insertAt, [
        RivRawObject(
          typeKey: RivTypeKeys.keyedObject,
          properties: [_uintProperty(RivPropertyKeys.keyedObjectId, objectId)],
        ),
        RivRawObject(
          typeKey: RivTypeKeys.keyedProperty,
          properties: [
            _uintProperty(RivPropertyKeys.keyedPropertyKey, propertyKey),
          ],
        ),
        _keyframe(frame, value),
      ]);
      return true;
    }

    // Locate (or create) the KeyedProperty inside the keyed object.
    var propertyStart = -1;
    var propertyEnd = keyedObjectEnd;
    for (var i = keyedObjectStart + 1; i < keyedObjectEnd; i++) {
      final object = document.objects[i];
      if (object.typeKey == RivTypeKeys.keyedObject) break;
      if (object.typeKey != RivTypeKeys.keyedProperty) continue;
      if (propertyStart >= 0) {
        propertyEnd = i;
        break;
      }
      final key = object.property(RivPropertyKeys.keyedPropertyKey);
      if (key != null && key.uintValue == propertyKey) propertyStart = i;
    }

    if (propertyStart < 0) {
      document.objects.insertAll(keyedObjectEnd, [
        RivRawObject(
          typeKey: RivTypeKeys.keyedProperty,
          properties: [
            _uintProperty(RivPropertyKeys.keyedPropertyKey, propertyKey),
          ],
        ),
        _keyframe(frame, value),
      ]);
      return true;
    }

    // Insert in frame order within the keyed property, replacing an
    // existing keyframe at the same frame.
    var insertAt = propertyEnd;
    for (var i = propertyStart + 1; i < propertyEnd; i++) {
      final object = document.objects[i];
      if (object.typeKey != RivTypeKeys.keyFrameDouble) continue;
      final existing =
          object.property(RivPropertyKeys.keyFrameFrame)?.uintValue ?? 0;
      if (existing == frame) {
        final valueProperty = object.property(
          RivPropertyKeys.keyFrameDoubleValue,
        );
        if (valueProperty != null) {
          valueProperty.floatValue = value;
        } else {
          object.properties.add(
            _floatProperty(RivPropertyKeys.keyFrameDoubleValue, value),
          );
        }
        return true;
      }
      if (existing > frame) {
        insertAt = i;
        break;
      }
    }
    document.objects.insert(insertAt, _keyframe(frame, value));
    return true;
  }

  /// Sets a uint property on animation [animationOrdinal] of artboard
  /// [artboardOrdinal] (loop mode, fps, duration). Returns `true` when
  /// the animation exists.
  static bool setAnimationUint(
    RivRawDocument document, {
    required int artboardOrdinal,
    required int animationOrdinal,
    required int propertyKey,
    required int value,
  }) {
    final span = _artboardSpan(document, artboardOrdinal);
    if (span == null) return false;
    final animation = _animationSpan(document, span, animationOrdinal);
    if (animation == null) return false;

    final object = document.objects[animation.start];
    final property = object.property(propertyKey);
    if (property != null) {
      if (property.uintValue == value) return true;
      property.uintValue = value;
    } else {
      object.properties.add(_uintProperty(propertyKey, value));
    }
    return true;
  }

  /// Removes the keyframe at raw object index [rawObjectIndex], pruning
  /// the owning KeyedProperty and KeyedObject when they become empty
  /// (the runtime rejects keyed containers without children).
  ///
  /// Returns `true` when a keyframe was removed.
  static bool deleteKeyframe(RivRawDocument document, int rawObjectIndex) {
    if (rawObjectIndex < 0 || rawObjectIndex >= document.objects.length) {
      return false;
    }
    final target = document.objects[rawObjectIndex];
    if (!RivTypeKeys.keyFrameTypeKeys.contains(target.typeKey)) return false;

    document.objects.removeAt(rawObjectIndex);

    // Walk back to the owning KeyedProperty; prune if it now has no
    // keyframes, then likewise for the owning KeyedObject.
    var propertyIndex = -1;
    for (var i = rawObjectIndex - 1; i >= 0; i--) {
      final typeKey = document.objects[i].typeKey;
      if (typeKey == RivTypeKeys.keyedProperty) {
        propertyIndex = i;
        break;
      }
      if (!RivTypeKeys.keyFrameTypeKeys.contains(typeKey) &&
          !RivTypeKeys.interpolatorTypeKeys.contains(typeKey)) {
        break;
      }
    }
    if (propertyIndex < 0) return true;

    final propertyHasKeyframes =
        propertyIndex + 1 < document.objects.length &&
        RivTypeKeys.keyFrameTypeKeys.contains(
          document.objects[propertyIndex + 1].typeKey,
        );
    if (propertyHasKeyframes) return true;
    document.objects.removeAt(propertyIndex);

    var keyedObjectIndex = -1;
    for (var i = propertyIndex - 1; i >= 0; i--) {
      final typeKey = document.objects[i].typeKey;
      if (typeKey == RivTypeKeys.keyedObject) {
        keyedObjectIndex = i;
        break;
      }
      if (typeKey != RivTypeKeys.keyedProperty &&
          !RivTypeKeys.keyFrameTypeKeys.contains(typeKey) &&
          !RivTypeKeys.interpolatorTypeKeys.contains(typeKey)) {
        break;
      }
    }
    if (keyedObjectIndex < 0) return true;

    final objectHasProperties =
        keyedObjectIndex + 1 < document.objects.length &&
        document.objects[keyedObjectIndex + 1].typeKey ==
            RivTypeKeys.keyedProperty;
    if (!objectHasProperties) {
      document.objects.removeAt(keyedObjectIndex);
    }
    return true;
  }

  static RivRawObject _keyframe(int frame, double value) => RivRawObject(
    typeKey: RivTypeKeys.keyFrameDouble,
    properties: [
      if (frame != 0) _uintProperty(RivPropertyKeys.keyFrameFrame, frame),
      _uintProperty(
        RivPropertyKeys.keyFrameInterpolationType,
        linearInterpolation,
      ),
      _floatProperty(RivPropertyKeys.keyFrameDoubleValue, value),
    ],
  );

  /// Raw-index range `[start, end)` of animation [animationOrdinal]
  /// inside the artboard span: `start` is the LinearAnimation object,
  /// `end` is the next LinearAnimation or the span end.
  static ({int start, int end})? _animationSpan(
    RivRawDocument document,
    ({int startRawIndex, int endRawIndex}) span,
    int animationOrdinal,
  ) {
    var seen = -1;
    for (var i = span.startRawIndex; i < span.endRawIndex; i++) {
      if (document.objects[i].typeKey != RivTypeKeys.linearAnimation) continue;
      seen++;
      if (seen != animationOrdinal) continue;
      var end = i + 1;
      while (end < span.endRawIndex &&
          document.objects[end].typeKey != RivTypeKeys.linearAnimation) {
        end++;
      }
      return (start: i, end: end);
    }
    return null;
  }

  /// Raw-index range of artboard [artboardOrdinal]'s objects.
  static ({int startRawIndex, int endRawIndex})? _artboardSpan(
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
      while (end < document.objects.length &&
          !topLevelTypes.contains(document.objects[end].typeKey)) {
        end++;
      }
      return (startRawIndex: i, endRawIndex: end);
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
}
