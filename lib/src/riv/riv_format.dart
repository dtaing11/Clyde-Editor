/// Constants describing the parts of the Rive object model the editor
/// understands, mirrored from `rive-runtime` generated headers.
///
/// Type keys identify object kinds; property keys identify serialized fields.
/// See `include/rive/generated/**` in the rive-runtime repository.
abstract final class RivTypeKeys {
  static const int artboard = 1;
  static const int backboard = 23;
  static const int keyedObject = 25;
  static const int keyedProperty = 26;
  static const int keyFrameDouble = 30;
  static const int linearAnimation = 31;
  static const int keyFrameColor = 37;
  static const int keyFrameId = 50;
  static const int stateMachine = 53;
  static const int keyFrameBool = 84;
  static const int keyFrameString = 142;
  static const int keyFrameUint = 450;

  /// Type keys that belong to the animation/state machine subsystem.
  ///
  /// Objects with these types are *not* artboard components and therefore
  /// do not consume a component index (keyed objects reference components
  /// by their index in the artboard's object list).
  static const Set<int> animationTypeKeys = {
    25, 26, 27, 28, 29, 30, 31, 37, 50, 53, 54, 55, 56, 57, 58, 59, 60, //
    61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
    78, 84, 95, 96, 97, 98, 114, 115, 116, 117, 118, 121, 122, 123, 124,
    125, 126, 138, 139, 142, 145, 163, 168, 169, 170, 171, 174, 175, 450,
    476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 496, 497,
    505, 527, 528, 593, 601, 602, 614, 615, 630, 646, 647, 652, 654, 667,
    671, 672, 1037, 1038,
  };

  /// Interpolator type keys. Although they live in the animation
  /// subsystem, the runtime imports them as artboard components
  /// (see `keyframe_interpolator.cpp`), so they consume object indices.
  static const Set<int> interpolatorTypeKeys = {28, 138, 139, 163, 174, 175};
}

/// Property keys the parser reads explicitly.
abstract final class RivPropertyKeys {
  // Component
  static const int componentName = 4;
  static const int componentParentId = 5;

  // Animation / LinearAnimation
  static const int animationName = 55;
  static const int animationFps = 56;
  static const int animationDuration = 57;

  // KeyedObject / KeyedProperty / KeyFrame
  static const int keyedObjectId = 51;
  static const int keyedPropertyKey = 53;
  static const int keyFrameFrame = 67;
  static const int keyFrameInterpolationType = 68;
  static const int keyFrameInterpolatorId = 69;
  static const int keyFrameDoubleValue = 70;
}

/// Serialized field categories used by the `.riv` property table of
/// contents (2 bits per property key). Mirrors `Core*Type::id`.
enum RivFieldType {
  /// Variable-length unsigned integer (also booleans).
  uint(0),

  /// Length-prefixed string or byte blob.
  string(1),

  /// 32-bit little-endian float.
  float(2),

  /// 32-bit little-endian color (RGBA).
  color(3);

  const RivFieldType(this.id);
  final int id;

  static RivFieldType fromId(int id) =>
      values.firstWhere((type) => type.id == id);
}

/// Human-readable names for animatable property keys, used by the timeline
/// track list. Extend as more of the object model is surfaced in the UI.
const Map<int, String> rivAnimatedPropertyNames = {
  13: 'X',
  14: 'Y',
  15: 'Rotation',
  16: 'Scale X',
  17: 'Scale Y',
  18: 'Opacity',
  20: 'Width',
  21: 'Height',
  37: 'Color',
  41: 'Position X',
  42: 'Position Y',
  47: 'Stroke Thickness',
  123: 'Origin X',
  124: 'Origin Y',
};
