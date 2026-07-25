import 'dart:ui';

import '../core/model/scene_node_ref.dart';
import '../core/services/scene_hit_tester.dart';
import 'riv_format.dart';
import 'riv_hierarchy.dart';
import 'riv_raw_document.dart';

/// Derives selectable hit regions from a document's raw objects.
///
/// A shape's region combines its node translation (x/y on the Shape)
/// with its parametric path size (width/height on Rectangle/Ellipse,
/// centred on the node). Group nodes contribute the union of their
/// children. Components without spatial data produce no region.
abstract final class RivHitRegions {
  /// Hit regions for artboard [artboardOrdinal] of [document].
  static List<SceneHitRegion> forArtboard(
    RivRawDocument document,
    int artboardOrdinal,
  ) {
    final trees = RivHierarchy.artboardTrees(document);
    if (artboardOrdinal < 0 || artboardOrdinal >= trees.length) {
      return const [];
    }

    final componentObjects = _componentObjects(document, artboardOrdinal);
    final regions = <SceneHitRegion>[];
    var drawOrder = 0;

    void visit(RivHierarchyNode node, Offset parentTranslation) {
      final object = componentObjects[node.componentIndex];
      final translation = parentTranslation + _translationOf(object);

      final size = _parametricChildSize(node, componentObjects);
      if (size != null) {
        regions.add(
          SceneHitRegion(
            ref: SceneNodeRef(artboardOrdinal, node.componentIndex),
            bounds: Rect.fromCenter(
              center: translation,
              width: size.width,
              height: size.height,
            ),
            drawOrder: drawOrder++,
          ),
        );
      }
      for (final child in node.children) {
        visit(child, translation);
      }
    }

    final root = trees[artboardOrdinal];
    for (final child in root.children) {
      visit(child, Offset.zero);
    }
    return regions;
  }

  /// Raw objects by component index for one artboard.
  static Map<int, RivRawObject> _componentObjects(
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

    final result = <int, RivRawObject>{};
    var seen = -1;
    for (var i = 0; i < document.objects.length; i++) {
      if (document.objects[i].typeKey != RivTypeKeys.artboard) continue;
      seen++;
      if (seen != artboardOrdinal) continue;

      var componentIndex = 0;
      result[componentIndex++] = document.objects[i];
      for (var j = i + 1; j < document.objects.length; j++) {
        final object = document.objects[j];
        if (topLevelTypes.contains(object.typeKey)) break;
        final isComponent =
            !RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
            RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey);
        if (isComponent) result[componentIndex++] = object;
      }
      break;
    }
    return result;
  }

  static Offset _translationOf(RivRawObject? object) {
    if (object == null) return Offset.zero;
    final x = object.property(RivPropertyKeys.nodeX);
    final y = object.property(RivPropertyKeys.nodeY);
    return Offset(
      x != null && x.fieldType == RivFieldType.float ? x.floatValue : 0,
      y != null && y.fieldType == RivFieldType.float ? y.floatValue : 0,
    );
  }

  /// Size of [node]'s parametric path child, or `null` when it has none.
  static Size? _parametricChildSize(
    RivHierarchyNode node,
    Map<int, RivRawObject> componentObjects,
  ) {
    const parametricTypes = {
      RivTypeKeys.rectangle,
      RivTypeKeys.ellipse,
      8, // Triangle
      51, // Polygon
      52, // Star
    };

    for (final child in node.children) {
      if (!parametricTypes.contains(child.typeKey)) continue;
      final object = componentObjects[child.componentIndex];
      final width = object?.property(RivPropertyKeys.layoutWidth);
      final height = object?.property(RivPropertyKeys.layoutHeight);
      if (width == null || height == null) continue;
      return Size(width.floatValue, height.floatValue);
    }
    return null;
  }
}
