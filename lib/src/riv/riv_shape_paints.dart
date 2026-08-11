import 'riv_format.dart';
import 'riv_hierarchy.dart';
import 'riv_raw_document.dart';

/// Resolves paint (fill/stroke) colours for components.
///
/// A shape's fill colour lives on a SolidColor nested under a Fill
/// child (Shape → Fill → SolidColor); text nests one level deeper
/// (Text → TextStylePaint → Fill → SolidColor). This helper walks the
/// hierarchy so callers address paints by the *component* they see in
/// the scene, not by paint internals.
abstract final class RivShapePaints {
  /// The fill SolidColor of component [componentIndex], or `null` when
  /// the component has no solid fill.
  static RivPaintTarget? fillOf(
    RivRawDocument document,
    int artboardOrdinal,
    int componentIndex,
  ) => _paintOf(document, artboardOrdinal, componentIndex, RivTypeKeys.fill);

  /// The stroke SolidColor of component [componentIndex], or `null`.
  static RivPaintTarget? strokeOf(
    RivRawDocument document,
    int artboardOrdinal,
    int componentIndex,
  ) => _paintOf(document, artboardOrdinal, componentIndex, RivTypeKeys.stroke);

  static RivPaintTarget? _paintOf(
    RivRawDocument document,
    int artboardOrdinal,
    int componentIndex,
    int paintTypeKey,
  ) {
    final trees = RivHierarchy.artboardTrees(document);
    if (artboardOrdinal < 0 || artboardOrdinal >= trees.length) return null;
    final node = _findNode(trees[artboardOrdinal], componentIndex);
    if (node == null) return null;

    final objects = RivHierarchy.componentObjects(document, artboardOrdinal);
    final solidColorNode = _findSolidColorUnderPaint(node, paintTypeKey);
    if (solidColorNode == null) return null;

    final object = objects[solidColorNode.componentIndex];
    final property = object?.property(RivPropertyKeys.solidColorValue);
    if (object == null || property == null) return null;
    return RivPaintTarget(
      solidColorComponentIndex: solidColorNode.componentIndex,
      color: property.colorValue,
    );
  }

  /// Depth-first search for the SolidColor beneath the first
  /// [paintTypeKey] (Fill/Stroke) child, looking through intermediate
  /// containers such as TextStylePaint.
  static RivHierarchyNode? _findSolidColorUnderPaint(
    RivHierarchyNode node,
    int paintTypeKey,
  ) {
    for (final child in node.children) {
      if (child.typeKey == paintTypeKey) {
        return _findSolidColor(child);
      }
      // Text nests paints under TextStylePaint.
      if (child.typeKey == RivTypeKeys.textStylePaint) {
        final found = _findSolidColorUnderPaint(child, paintTypeKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  static RivHierarchyNode? _findSolidColor(RivHierarchyNode paint) {
    for (final child in paint.children) {
      if (child.typeKey == RivTypeKeys.solidColor) return child;
      final nested = _findSolidColor(child);
      if (nested != null) return nested;
    }
    return null;
  }

  static RivHierarchyNode? _findNode(RivHierarchyNode root, int index) {
    if (root.componentIndex == index) return root;
    for (final child in root.children) {
      final found = _findNode(child, index);
      if (found != null) return found;
    }
    return null;
  }
}

/// A resolved paint colour: where it lives and its current value.
final class RivPaintTarget {
  const RivPaintTarget({
    required this.solidColorComponentIndex,
    required this.color,
  });

  /// Component index of the SolidColor object holding the colour.
  final int solidColorComponentIndex;

  /// Current ARGB value.
  final int color;
}
