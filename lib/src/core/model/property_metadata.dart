/// Metadata describing one editable property of a component type
/// (§2.5: the inspector is generated from metadata, never hand-written
/// per node type).
final class PropertyDescriptor {
  const PropertyDescriptor({
    required this.key,
    required this.label,
    required this.group,
    this.min,
    this.max,
    this.dragStep = 1,
    this.defaultValue = 0,
  });

  /// Rive property key (float-typed; other field types get their own
  /// descriptor classes when the inspector grows past numerics).
  final int key;

  final String label;

  /// Section header the property renders under.
  final String group;

  final double? min;
  final double? max;

  /// Value change per logical drag pixel in the numeric field.
  final double dragStep;

  /// Value assumed when the property is absent from the object (the
  /// runtime's default, so writing it is always safe).
  final double defaultValue;
}

/// Registry mapping component type keys to their editable properties
/// (§4.5: adding a node type or property is a registration).
final class PropertyMetadataRegistry {
  PropertyMetadataRegistry();

  /// Built-in registry covering the Phase 1 object model.
  factory PropertyMetadataRegistry.standard() {
    const transform = 'Transform';
    const size = 'Size';

    const nodeX = PropertyDescriptor(key: 13, label: 'X', group: transform);
    const nodeY = PropertyDescriptor(key: 14, label: 'Y', group: transform);
    const rotation = PropertyDescriptor(
      key: 15,
      label: 'Rotation',
      group: transform,
      dragStep: 0.02,
    );
    const scaleX = PropertyDescriptor(
      key: 16,
      label: 'Scale X',
      group: transform,
      dragStep: 0.01,
      defaultValue: 1,
    );
    const scaleY = PropertyDescriptor(
      key: 17,
      label: 'Scale Y',
      group: transform,
      dragStep: 0.01,
      defaultValue: 1,
    );
    const opacity = PropertyDescriptor(
      key: 18,
      label: 'Opacity',
      group: transform,
      min: 0,
      max: 1,
      dragStep: 0.005,
      defaultValue: 1,
    );
    const pathWidth = PropertyDescriptor(
      key: 20,
      label: 'Width',
      group: size,
      min: 0,
    );
    const pathHeight = PropertyDescriptor(
      key: 21,
      label: 'Height',
      group: size,
      min: 0,
    );

    const transformable = [nodeX, nodeY, rotation, scaleX, scaleY, opacity];

    final registry = PropertyMetadataRegistry();
    // Node-like containers.
    registry.register(2, transformable); // Node
    registry.register(3, transformable); // Shape
    registry.register(40, transformable); // Bone
    registry.register(41, transformable); // RootBone
    registry.register(134, transformable); // Text
    // Parametric paths.
    const parametric = [pathWidth, pathHeight];
    registry.register(7, parametric); // Rectangle
    registry.register(4, parametric); // Ellipse
    registry.register(8, parametric); // Triangle
    registry.register(51, parametric); // Polygon
    registry.register(52, parametric); // Star
    return registry;
  }

  final Map<int, List<PropertyDescriptor>> _byTypeKey = {};

  void register(int typeKey, List<PropertyDescriptor> descriptors) {
    _byTypeKey[typeKey] = List.unmodifiable(descriptors);
  }

  /// Editable properties of [typeKey]; empty when none registered.
  List<PropertyDescriptor> forType(int typeKey) =>
      _byTypeKey[typeKey] ?? const [];
}
