import 'dart:ui';

import '../model/scene_node_ref.dart';

/// A selectable region in scene space, produced by the document layer
/// and consumed by canvas hit testing.
final class SceneHitRegion {
  const SceneHitRegion({
    required this.ref,
    required this.bounds,
    required this.drawOrder,
  });

  final SceneNodeRef ref;

  /// Axis-aligned bounds in artboard/scene coordinates.
  final Rect bounds;

  /// Later objects draw on top; hit testing prefers the topmost.
  final int drawOrder;
}

/// Point and rect queries over a set of [SceneHitRegion]s.
///
/// Regions are kept sorted by draw order so point queries return the
/// topmost hit first (§2.3). The index is rebuilt only when the
/// document changes, never per pointer event.
final class SceneHitTester {
  SceneHitTester(Iterable<SceneHitRegion> regions)
    : _byTopmost = regions.toList()
        ..sort((a, b) => b.drawOrder.compareTo(a.drawOrder));

  final List<SceneHitRegion> _byTopmost;

  bool get isEmpty => _byTopmost.isEmpty;
  int get regionCount => _byTopmost.length;

  /// The topmost region containing [scenePoint], or `null`.
  SceneHitRegion? hitTest(Offset scenePoint) {
    for (final region in _byTopmost) {
      if (region.bounds.contains(scenePoint)) return region;
    }
    return null;
  }

  /// All regions intersecting [sceneRect] (marquee selection).
  List<SceneHitRegion> hitTestRect(Rect sceneRect) {
    return [
      for (final region in _byTopmost)
        if (region.bounds.overlaps(sceneRect)) region,
    ];
  }

  /// Bounds of [ref], or `null` when it has no region.
  Rect? boundsOf(SceneNodeRef ref) {
    for (final region in _byTopmost) {
      if (region.ref == ref) return region.bounds;
    }
    return null;
  }
}
