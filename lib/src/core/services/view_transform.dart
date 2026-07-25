import 'dart:math' as math;
import 'dart:ui';

/// The single source of truth for the canvas view transform (§2.3:
/// consumed by content, overlay, and interaction layers alike).
///
/// Maps between *scene* coordinates (artboard space) and *view*
/// coordinates (widget-local pixels): `view = scene * scale + offset`.
final class ViewTransform {
  const ViewTransform({this.scale = 1, this.offset = Offset.zero});

  static const double minScale = 0.1;
  static const double maxScale = 8;

  final double scale;
  final Offset offset;

  Offset sceneToView(Offset scenePoint) => scenePoint * scale + offset;

  Offset viewToScene(Offset viewPoint) => (viewPoint - offset) / scale;

  ViewTransform copyWith({double? scale, Offset? offset}) =>
      ViewTransform(scale: scale ?? this.scale, offset: offset ?? this.offset);

  /// Pans by [delta] in view pixels.
  ViewTransform pannedBy(Offset delta) => copyWith(offset: offset + delta);

  /// Zooms towards [viewAnchor] so the scene point under the cursor
  /// stays fixed while scaling.
  ViewTransform zoomedBy(double factor, {required Offset viewAnchor}) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    if (newScale == scale) return this;
    final sceneAnchor = viewToScene(viewAnchor);
    return ViewTransform(
      scale: newScale,
      offset: viewAnchor - sceneAnchor * newScale,
    );
  }

  /// A transform that fits [sceneSize] into [viewSize] with [padding].
  static ViewTransform fit(
    Size sceneSize,
    Size viewSize, {
    double padding = 48,
  }) {
    if (sceneSize.isEmpty || viewSize.isEmpty) return const ViewTransform();
    final available = Size(
      math.max(1, viewSize.width - padding * 2),
      math.max(1, viewSize.height - padding * 2),
    );
    final scale = math
        .min(
          available.width / sceneSize.width,
          available.height / sceneSize.height,
        )
        .clamp(minScale, maxScale)
        .toDouble();
    final scaled = sceneSize * scale;
    return ViewTransform(
      scale: scale,
      offset: Offset(
        (viewSize.width - scaled.width) / 2,
        (viewSize.height - scaled.height) / 2,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ViewTransform && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}
