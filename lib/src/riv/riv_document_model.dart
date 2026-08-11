import 'riv_format.dart';

/// Lightweight editor-side model of a `.riv` file's animation data.
///
/// This intentionally only models what the timeline needs (keyed objects,
/// keyed properties, keyframes). Rendering and playback stay with the
/// native engine; this model exists so the editor can *display and edit*
/// keyframes.
class RivDocumentModel {
  const RivDocumentModel({
    required this.majorVersion,
    required this.minorVersion,
    required this.artboards,
  });

  final int majorVersion;
  final int minorVersion;
  final List<RivArtboardModel> artboards;
}

/// An artboard and the animations parsed from it.
class RivArtboardModel {
  RivArtboardModel({required this.name});

  final String name;
  final List<RivAnimationModel> animations = [];

  /// Component names by artboard object index, used to resolve
  /// [RivKeyedObjectModel.objectId] to a display name.
  final Map<int, String> componentNames = {};

  /// Cubic ease control points by interpolator component index.
  final Map<int, RivCubicEase> cubicEases = {};
}

/// A linear animation with its keyed object tree.
class RivAnimationModel {
  RivAnimationModel({
    required this.name,
    required this.fps,
    required this.durationFrames,
    this.loop = RivLoopMode.loop,
  });

  final String name;
  final int fps;
  final int durationFrames;

  /// How playback behaves at the end of the animation.
  final RivLoopMode loop;

  final List<RivKeyedObjectModel> keyedObjects = [];

  double get durationSeconds => fps > 0 ? durationFrames / fps : 0;
}

/// LinearAnimation.loopValue semantics (`rive::Loop`).
enum RivLoopMode {
  oneShot(0),
  loop(1),
  pingPong(2);

  const RivLoopMode(this.value);

  /// Serialized loopValue.
  final int value;

  static RivLoopMode fromValue(int value) => switch (value) {
    0 => RivLoopMode.oneShot,
    2 => RivLoopMode.pingPong,
    _ => RivLoopMode.loop,
  };
}

/// All keyed properties for one animated component.
class RivKeyedObjectModel {
  RivKeyedObjectModel({required this.objectId, required String objectName})
    : _objectName = objectName; // ignore: prefer_initializing_formals

  /// Index of the animated component in the artboard object list.
  final int objectId;

  String _objectName;

  /// Resolved display name (component name or a fallback).
  String get objectName => _objectName;

  /// Called by the parser once component names are known.
  void resolveName(String name) => _objectName = name;

  final List<RivKeyedPropertyModel> properties = [];
}

/// A single animated property track (e.g. "X" of a node).
class RivKeyedPropertyModel {
  RivKeyedPropertyModel({required this.propertyKey});

  /// Rive property key being animated (e.g. 13 for Node.x).
  final int propertyKey;

  final List<RivKeyFrameModel> keyframes = [];

  List<RivKeyFrameModel>? _numericCache;

  /// Keyframes with numeric values, cached: the model is immutable
  /// after parse (edits rebuild it), so evaluation hot paths (curve
  /// repaints sample per pixel) avoid re-filtering 10k keyframes.
  List<RivKeyFrameModel> get numericKeyframes => _numericCache ??= [
    for (final keyframe in keyframes)
      if (keyframe.value != null) keyframe,
  ];

  /// Invalidates [numericKeyframes] after in-place keyframe edits.
  void invalidateCache() => _numericCache = null;

  /// Display name for the track.
  String get displayName =>
      rivAnimatedPropertyNames[propertyKey] ?? 'Property $propertyKey';
}

/// Interpolation type of a keyframe, mirrored from the runtime.
enum RivInterpolationType {
  hold(0),
  linear(1),
  cubic(2),
  cubicValue(3);

  const RivInterpolationType(this.id);
  final int id;

  static RivInterpolationType fromId(int id) => values.firstWhere(
    (type) => type.id == id,
    orElse: () => RivInterpolationType.linear,
  );
}

/// A single keyframe on a property track.
class RivKeyFrameModel {
  RivKeyFrameModel({
    required this.frame,
    required this.interpolation,
    this.value,
    this.rawObjectIndex = -1,
    this.interpolatorId = -1,
  });

  /// Position in frames (divide by animation fps for seconds).
  final int frame;

  final RivInterpolationType interpolation;

  /// Numeric value for double keyframes; `null` for other kinds
  /// (color/id/bool) until the editor supports editing them.
  final double? value;

  /// Index of the backing object in the raw document, used to map this
  /// keyframe back to bytes when editing. `-1` for synthetic keyframes.
  final int rawObjectIndex;

  /// Component index of the referenced interpolator, `-1` when none.
  final int interpolatorId;

  /// Cubic bezier ease of the referenced interpolator; resolved by the
  /// parser after all components are known. `null` for non-cubic
  /// keyframes or unresolved interpolators.
  RivCubicEase? cubic;

  double timeInSeconds(int fps) => fps > 0 ? frame / fps : 0;
}

/// Control points of a CubicEaseInterpolator (css-style bezier ease).
final class RivCubicEase {
  const RivCubicEase({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  /// Standard ease-in-out (matches the web's `ease-in-out`).
  static const RivCubicEase easeInOut = RivCubicEase(
    x1: 0.42,
    y1: 0,
    x2: 0.58,
    y2: 1,
  );

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}
