import 'dart:typed_data';

import 'riv_document_model.dart';
import 'riv_format.dart';
import 'riv_parser.dart';
import 'riv_raw_document.dart';

/// Applies edits to a `.riv` document and produces updated bytes.
///
/// Owns a [RivRawDocument] (lossless byte-level representation) and the
/// [RivDocumentModel] display model derived from it. Edits mutate the raw
/// object stream; [bytes] serializes the result, and [model] is rebuilt
/// so UI and engine stay in sync.
class RivDocumentEditor {
  RivDocumentEditor._(this._raw) : model = RivParser.fromRaw(_raw);

  final RivRawDocument _raw;

  /// Display model matching the current state of the document.
  RivDocumentModel model;

  /// Parses [bytes] into an editable document, or throws
  /// [RivFormatException] on invalid input.
  static RivDocumentEditor parse(Uint8List bytes) {
    return RivDocumentEditor._(RivRawDocument.parse(bytes));
  }

  /// Serializes the current state to `.riv` bytes.
  Uint8List bytes() => _raw.serialize();

  /// Moves [keyframe] to [newFrame], clamped to `0..durationFrames`.
  ///
  /// Returns `true` when the document changed. The display [model] is
  /// rebuilt so keyframe ordering and track contents stay consistent.
  bool retimeKeyframe(
    RivKeyFrameModel keyframe,
    int newFrame, {
    required int durationFrames,
  }) {
    final object = _rawKeyFrameObject(keyframe);
    if (object == null) return false;

    final clamped = newFrame.clamp(0, durationFrames);
    if (clamped == keyframe.frame) return false;

    final frameProperty = object.property(RivPropertyKeys.keyFrameFrame);
    if (frameProperty == null) {
      // Frame 0 keyframes may omit the property; add it explicitly.
      if (clamped == 0) return false;
      object.properties.add(
        RivRawProperty(
          key: RivPropertyKeys.keyFrameFrame,
          fieldType: RivFieldType.uint,
          valueBytes: Uint8List(0),
        )..uintValue = clamped,
      );
    } else {
      frameProperty.uintValue = clamped;
    }
    _rebuild();
    return true;
  }

  /// Sets the numeric value of a double [keyframe] to [newValue].
  ///
  /// Returns `true` when the document changed.
  bool setKeyframeValue(RivKeyFrameModel keyframe, double newValue) {
    final object = _rawKeyFrameObject(keyframe);
    if (object == null || object.typeKey != RivTypeKeys.keyFrameDouble) {
      return false;
    }
    final valueProperty = object.property(RivPropertyKeys.keyFrameDoubleValue);
    if (valueProperty == null) {
      object.properties.add(
        RivRawProperty(
          key: RivPropertyKeys.keyFrameDoubleValue,
          fieldType: RivFieldType.float,
          valueBytes: Uint8List(0),
        )..floatValue = newValue,
      );
    } else {
      if (valueProperty.floatValue == newValue) return false;
      valueProperty.floatValue = newValue;
    }
    _rebuild();
    return true;
  }

  RivRawObject? _rawKeyFrameObject(RivKeyFrameModel keyframe) {
    final index = keyframe.rawObjectIndex;
    if (index < 0 || index >= _raw.objects.length) return null;
    final object = _raw.objects[index];
    const keyFrameTypes = {
      RivTypeKeys.keyFrameDouble,
      RivTypeKeys.keyFrameColor,
      RivTypeKeys.keyFrameId,
      RivTypeKeys.keyFrameBool,
      RivTypeKeys.keyFrameUint,
      RivTypeKeys.keyFrameString,
    };
    return keyFrameTypes.contains(object.typeKey) ? object : null;
  }

  void _rebuild() {
    model = RivParser.fromRaw(_raw);
  }
}
