import 'riv_format.dart';
import 'riv_raw_document.dart';

/// A node in an artboard's component tree.
class RivHierarchyNode {
  RivHierarchyNode({
    required this.componentIndex,
    required this.typeKey,
    required this.name,
  });

  /// Index of this component in the artboard's object list (the same
  /// index space keyed objects use).
  final int componentIndex;

  final int typeKey;
  final String name;
  final List<RivHierarchyNode> children = [];

  /// Human-readable label combining name and type.
  String get label => name.isNotEmpty ? name : typeDisplayName;

  String get typeDisplayName => _typeNames[typeKey] ?? 'Component ($typeKey)';

  static const Map<int, String> _typeNames = {
    RivTypeKeys.artboard: 'Artboard',
    RivTypeKeys.node: 'Node',
    RivTypeKeys.shape: 'Shape',
    RivTypeKeys.ellipse: 'Ellipse',
    RivTypeKeys.rectangle: 'Rectangle',
    16: 'Path',
    RivTypeKeys.solidColor: 'Solid Color',
    RivTypeKeys.fill: 'Fill',
    RivTypeKeys.stroke: 'Stroke',
    RivTypeKeys.bone: 'Bone',
    RivTypeKeys.rootBone: 'Root Bone',
    RivTypeKeys.text: 'Text',
    5: 'Point',
    17: 'Vertex',
    22: 'Gradient Stop',
    19: 'Linear Gradient',
    42: 'Clipping Shape',
  };
}

/// An asset embedded in or referenced by the file.
class RivAssetInfo {
  const RivAssetInfo({
    required this.name,
    required this.typeKey,
    required this.assetId,
    required this.isEmbedded,
    required this.sizeBytes,
  });

  final String name;
  final int typeKey;
  final int assetId;

  /// Whether the asset bytes are stored in the file (vs. referenced).
  final bool isEmbedded;

  /// Byte size of embedded contents, 0 for referenced assets.
  final int sizeBytes;

  String get typeDisplayName => switch (typeKey) {
    RivTypeKeys.imageAsset => 'Image',
    RivTypeKeys.fontAsset => 'Font',
    RivTypeKeys.audioAsset => 'Audio',
    _ => 'Asset',
  };
}

/// Builds component trees and asset lists from a raw document.
///
/// Components within an artboard reference their parent via
/// `parentId` (property 5), which indexes into the artboard's object
/// list in import order, the same index space used by keyed objects.
abstract final class RivHierarchy {
  /// Component trees per artboard, in file order.
  static List<RivHierarchyNode> artboardTrees(RivRawDocument document) {
    final trees = <RivHierarchyNode>[];
    List<RivHierarchyNode>? components;

    for (final object in document.objects) {
      if (object.typeKey == RivTypeKeys.artboard) {
        final root = _node(object, 0);
        trees.add(root);
        components = [root];
        continue;
      }
      if (components == null) continue;

      final isComponent =
          !RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
          RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey);
      if (!isComponent) continue;

      final node = _node(object, components.length);
      components.add(node);

      final parentProperty = object.property(RivPropertyKeys.componentParentId);
      if (parentProperty != null &&
          parentProperty.fieldType == RivFieldType.uint) {
        final parentId = parentProperty.uintValue;
        if (parentId < components.length - 1 || parentId == 0) {
          components[parentId].children.add(node);
          continue;
        }
      }
      // No/invalid parent: attach to the artboard root.
      components.first.children.add(node);
    }
    return trees;
  }

  /// All assets defined in [document], in file order.
  static List<RivAssetInfo> assets(RivRawDocument document) {
    final result = <RivAssetInfo>[];
    for (var i = 0; i < document.objects.length; i++) {
      final object = document.objects[i];
      if (object.typeKey != RivTypeKeys.imageAsset &&
          object.typeKey != RivTypeKeys.fontAsset &&
          object.typeKey != RivTypeKeys.audioAsset) {
        continue;
      }

      final nameProperty = object.property(RivPropertyKeys.assetName);
      final idProperty = object.property(RivPropertyKeys.assetId);

      // Contents follow the asset object when embedded.
      var isEmbedded = false;
      var sizeBytes = 0;
      if (i + 1 < document.objects.length) {
        final next = document.objects[i + 1];
        if (next.typeKey == RivTypeKeys.fileAssetContents) {
          isEmbedded = true;
          final bytesProperty = next.property(RivPropertyKeys.assetBytes);
          if (bytesProperty != null) {
            sizeBytes = bytesProperty.valueBytes.length;
          }
        }
      }

      result.add(
        RivAssetInfo(
          name:
              nameProperty != null &&
                  nameProperty.fieldType == RivFieldType.string
              ? _decodeString(nameProperty.valueBytes)
              : '',
          typeKey: object.typeKey,
          assetId:
              idProperty != null && idProperty.fieldType == RivFieldType.uint
              ? idProperty.uintValue
              : -1,
          isEmbedded: isEmbedded,
          sizeBytes: sizeBytes,
        ),
      );
    }
    return result;
  }

  static RivHierarchyNode _node(RivRawObject object, int index) {
    final nameProperty = object.property(RivPropertyKeys.componentName);
    return RivHierarchyNode(
      componentIndex: index,
      typeKey: object.typeKey,
      name:
          nameProperty != null && nameProperty.fieldType == RivFieldType.string
          ? _decodeString(nameProperty.valueBytes)
          : '',
    );
  }

  static String _decodeString(List<int> lengthPrefixed) {
    var length = 0;
    var shift = 0;
    var offset = 0;
    while (offset < lengthPrefixed.length) {
      final byte = lengthPrefixed[offset++];
      length |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return String.fromCharCodes(
      lengthPrefixed.sublist(offset, offset + length),
    );
  }
}
