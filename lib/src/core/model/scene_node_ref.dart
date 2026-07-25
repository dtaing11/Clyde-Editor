/// Location of a component in the document: which artboard tree it
/// lives in plus its component index within that artboard.
///
/// Lives in `core/model` because selection, commands, and every panel
/// address components this way (§4.3: features communicate through
/// core, never through each other).
final class SceneNodeRef {
  const SceneNodeRef(this.artboardOrdinal, this.componentIndex);

  final int artboardOrdinal;
  final int componentIndex;

  @override
  bool operator ==(Object other) =>
      other is SceneNodeRef &&
      other.artboardOrdinal == artboardOrdinal &&
      other.componentIndex == componentIndex;

  @override
  int get hashCode => Object.hash(artboardOrdinal, componentIndex);

  @override
  String toString() => 'SceneNodeRef($artboardOrdinal:$componentIndex)';
}
