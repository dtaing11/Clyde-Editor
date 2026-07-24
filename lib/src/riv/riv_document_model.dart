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
}

/// A linear animation with its keyed object tree.
class RivAnimationModel {
  RivAnimationModel({
    required this.name,
    required this.fps,
    required this.durationFrames,
  });

  final String name;
  final int fps;
  final int durationFrames;
  final List<RivKeyedObjectModel> keyedObjects = [];

  double get durationSeconds => fps > 0 ? durationFrames / fps : 0;
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
  const RivKeyFrameModel({
    required this.frame,
    required this.interpolation,
    this.value,
    this.rawObjectIndex = -1,
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

  double timeInSeconds(int fps) => fps > 0 ? frame / fps : 0;
}
