import 'dart:typed_data';

import 'riv_binary_reader.dart';
import 'riv_binary_writer.dart';
import 'riv_component_refs.dart';
import 'riv_format.dart';
import 'riv_raw_document.dart';

/// Result of a structural operation.
///
/// [remap] maps old component indices to new ones (`-1` for removed
/// components) so callers can migrate any editor-side state keyed by
/// component index (selection, locks, expansion).
class RivStructuralResult {
  const RivStructuralResult.success(this.remap) : succeeded = true;
  const RivStructuralResult.failure()
    : succeeded = false,
      remap = const {};

  final bool succeeded;
  final Map<int, int> remap;
}

/// Structural editing of one artboard's component tree inside a
/// [RivRawDocument]: rename, reparent/reorder, duplicate, delete, and
/// visibility.
///
/// ## Correctness model
///
/// Components are addressed by their index in the artboard's object
/// list, and many runtime properties store such indices (see
/// [RivComponentRefs]). Every structural operation therefore runs a
/// three-phase pipeline:
///
/// 1. *Resolve*: each reference property is resolved to the referenced
///    object's identity.
/// 2. *Mutate*: raw objects are inserted, moved, or removed on a working
///    copy of the object list.
/// 3. *Commit*: component indices are recomputed and every reference is
///    rewritten from object identity. Dangling references are healed by
///    a fixed policy (cascade-delete owners, drop keyed blocks, or drop
///    nullable interpolator links). If healing is impossible the whole
///    operation is rolled back and reported as failed.
class RivArtboardEditor {
  RivArtboardEditor(this.document, this.artboardOrdinal);

  final RivRawDocument document;

  /// Which artboard to edit (0-based, in file order).
  final int artboardOrdinal;

  /// Reference keys that may simply be removed when their target
  /// disappears (the runtime treats a missing property as "none").
  static const Set<int> _droppableReferenceKeys = {69, 350, 591, 714, 758};

  /// Object types forming a keyed-animation block under a KeyedObject.
  static const Set<int> _keyedBlockTypes = {
    RivTypeKeys.keyedProperty,
    29, 30, 37, 50, 84, 142, 450, 170, 171,
  };

  // -- Public operations ---------------------------------------------------

  /// Renames the component at [componentIndex].
  bool rename(int componentIndex, String newName) {
    final span = _Span.of(document, artboardOrdinal);
    if (span == null) return false;
    final object = span.componentAt(componentIndex);
    if (object == null) return false;

    final encoded = (RivBinaryWriter()
          ..writeBytes(Uint8List.fromList(newName.codeUnits)))
        .takeBytes();
    final property = object.property(RivPropertyKeys.componentName);
    if (property != null) {
      property.valueBytes = encoded;
    } else {
      object.properties.insert(
        0,
        RivRawProperty(
          key: RivPropertyKeys.componentName,
          fieldType: RivFieldType.string,
          valueBytes: encoded,
        ),
      );
    }
    return true;
  }

  /// Toggles the runtime `Hidden` drawable flag.
  ///
  /// Returns false for components that carry no drawable flags (groups,
  /// bones); hiding those is a UI-level concern, not a file property.
  bool setHidden(int componentIndex, bool hidden) {
    const drawableFlagsKey = 129;
    const hiddenBit = 1;

    final span = _Span.of(document, artboardOrdinal);
    if (span == null) return false;
    final object = span.componentAt(componentIndex);
    if (object == null || componentIndex == 0) return false;

    final property = object.property(drawableFlagsKey);
    final current = property?.uintValue ?? 0;
    final updated = hidden ? (current | hiddenBit) : (current & ~hiddenBit);
    if (property != null) {
      property.uintValue = updated;
    } else {
      if (!hidden) return true;
      object.properties.add(
        RivRawProperty(
          key: drawableFlagsKey,
          fieldType: RivFieldType.uint,
          valueBytes: Uint8List(0),
        )..uintValue = updated,
      );
    }
    return true;
  }

  /// Whether the component currently has the `Hidden` flag set.
  bool isHidden(int componentIndex) {
    final span = _Span.of(document, artboardOrdinal);
    final object = span?.componentAt(componentIndex);
    final property = object?.property(129);
    return property != null && (property.uintValue & 1) != 0;
  }

  /// Moves [componentIndex] (with its whole subtree) under
  /// [newParentIndex]. When [insertAfterSibling] is given, the subtree
  /// lands right after that sibling's subtree; otherwise it becomes the
  /// first child.
  RivStructuralResult reparent(
    int componentIndex,
    int newParentIndex, {
    int? insertAfterSibling,
  }) {
    return _transact((span) {
      if (componentIndex == 0) return null;
      final moved = span.componentAt(componentIndex);
      final parent = span.componentAt(newParentIndex);
      if (moved == null || parent == null) return null;

      final subtree = span.subtreeOf(componentIndex);
      if (subtree.contains(newParentIndex)) return null; // Own descendant.

      final movedObjects = span.rawObjectsOfComponents(subtree);
      document.objects.removeWhere(movedObjects.contains);

      final anchor = insertAfterSibling != null
          ? span.lastRawObjectOfSubtree(insertAfterSibling, exclude: subtree)
          : parent;
      var insertAt = document.objects.indexOf(anchor) + 1;
      document.objects.insertAll(insertAt, movedObjects);

      return _ReferencePlan.forReparent(moved, parent);
    });
  }

  /// Duplicates the subtree at [componentIndex]; the copy is appended
  /// after the original subtree with " copy" suffixed to its name.
  RivStructuralResult duplicate(int componentIndex) {
    return _transact((span) {
      if (componentIndex == 0) return null;
      final original = span.componentAt(componentIndex);
      if (original == null) return null;

      final subtree = span.subtreeOf(componentIndex);
      final originals = span.rawObjectsOfComponents(subtree);
      final clones = [for (final o in originals) _cloneObject(o)];
      final cloneByOriginal = {
        for (var i = 0; i < originals.length; i++) originals[i]: clones[i],
      };

      final insertAt = document.objects.indexOf(originals.last) + 1;
      document.objects.insertAll(insertAt, clones);

      final cloneRoot = cloneByOriginal[original]!;
      _appendCopySuffix(cloneRoot);

      return _ReferencePlan.forDuplicate(
        span: span,
        cloneByOriginal: cloneByOriginal,
        cloneRootParent: span.parentObjectOf(componentIndex),
        cloneRoot: cloneRoot,
      );
    });
  }

  /// Deletes the subtree at [componentIndex], cascading to anything that
  /// would otherwise hold a dangling reference.
  RivStructuralResult delete(int componentIndex) {
    return _transact((span) {
      if (componentIndex == 0) return null;
      final subtree = span.subtreeOf(componentIndex);
      final removed = span.rawObjectsOfComponents(subtree);
      document.objects.removeWhere(removed.contains);
      return _ReferencePlan.forDelete(removed.toSet());
    });
  }

  // -- Pipeline ------------------------------------------------------------

  RivStructuralResult _transact(_ReferencePlan? Function(_Span) mutate) {
    final before = List.of(document.objects);
    final span = _Span.of(document, artboardOrdinal);
    if (span == null) return const RivStructuralResult.failure();

    final oldComponents = span.components;
    final resolved = _resolveReferences(span);

    final plan = mutate(span);
    if (plan == null) {
      document.objects
        ..clear()
        ..addAll(before);
      return const RivStructuralResult.failure();
    }

    final committed = _commit(span, resolved, plan);
    if (committed == null) {
      document.objects
        ..clear()
        ..addAll(before);
      return const RivStructuralResult.failure();
    }

    final remap = <int, int>{
      for (var i = 0; i < oldComponents.length; i++)
        i: committed[oldComponents[i]] ?? -1,
    };
    return RivStructuralResult.success(remap);
  }

  /// Resolves every reference property in the span to object identities.
  _ResolvedReferences _resolveReferences(_Span span) {
    final singles = <RivRawProperty, RivRawObject>{};
    final lists = <RivRawProperty, List<RivRawObject>>{};

    for (final object in span.allObjects) {
      for (final property in object.properties) {
        if (RivComponentRefs.uintReferenceKeys.contains(property.key) &&
            property.fieldType == RivFieldType.uint) {
          final target = span.componentAt(property.uintValue);
          if (target != null) singles[property] = target;
        } else if (RivComponentRefs.listReferenceKeys.contains(property.key)) {
          final targets = <RivRawObject>[];
          for (final id in _decodeVarUintList(property.valueBytes)) {
            final target = span.componentAt(id);
            if (target == null) {
              targets.clear();
              break;
            }
            targets.add(target);
          }
          if (targets.isNotEmpty) lists[property] = targets;
        }
      }
    }
    return _ResolvedReferences(singles, lists);
  }

  /// Rewrites references from identity, healing dangling ones. Returns
  /// the new identity-to-index mapping, or `null` when the document
  /// cannot be made consistent.
  Map<RivRawObject, int>? _commit(
    _Span span,
    _ResolvedReferences resolved,
    _ReferencePlan plan,
  ) {
    final deleted = Set.of(plan.deleted);

    // Cascade until no surviving object references a deleted component.
    while (true) {
      final freshSpan = _Span.of(document, artboardOrdinal);
      if (freshSpan == null) return null;

      final toRemove = <RivRawObject>{};
      for (final object in freshSpan.allObjects) {
        if (deleted.contains(object)) continue;
        for (final property in object.properties) {
          final target = plan.redirect(object, property, resolved);
          if (target == null || !deleted.contains(target)) continue;

          if (property.key == RivPropertyKeys.keyedObjectId) {
            toRemove.addAll(_keyedBlockOf(object));
          } else if (_droppableReferenceKeys.contains(property.key)) {
            // Healed later by dropping the property.
          } else if (freshSpan.isComponent(object)) {
            toRemove.addAll(
              freshSpan.rawObjectsOfComponents(
                freshSpan.subtreeOf(freshSpan.indexOfComponent(object)),
              ),
            );
          } else {
            toRemove.add(object);
          }
        }
        for (final property in object.properties) {
          final targets = resolved.lists[property];
          if (targets != null && targets.any(deleted.contains)) {
            return null; // Data-bind paths cannot be healed safely.
          }
        }
      }

      if (toRemove.isEmpty) break;
      deleted.addAll(toRemove);
      document.objects.removeWhere(toRemove.contains);
    }

    final finalSpan = _Span.of(document, artboardOrdinal);
    if (finalSpan == null) return null;
    final newIndex = {
      for (var i = 0; i < finalSpan.components.length; i++)
        finalSpan.components[i]: i,
    };

    // Rewrite all surviving references.
    for (final object in finalSpan.allObjects) {
      object.properties.removeWhere((property) {
        final target = plan.redirect(object, property, resolved);
        if (target == null) return false;
        final index = newIndex[target];
        if (index == null) {
          assert(_droppableReferenceKeys.contains(property.key));
          return true;
        }
        property.uintValue = index;
        return false;
      });
      for (final property in object.properties) {
        final targets = resolved.lists[property];
        if (targets != null) {
          property.valueBytes = _encodeVarUintList([
            for (final target in targets) newIndex[target]!,
          ]);
        }
      }
    }
    return newIndex;
  }

  /// The keyed-animation block owned by [keyedObject]: itself plus the
  /// keyed properties, keyframes, and interpolators that follow it.
  List<RivRawObject> _keyedBlockOf(RivRawObject keyedObject) {
    final start = document.objects.indexOf(keyedObject);
    if (start < 0) return const [];
    final block = <RivRawObject>[keyedObject];
    for (var i = start + 1; i < document.objects.length; i++) {
      final typeKey = document.objects[i].typeKey;
      if (_keyedBlockTypes.contains(typeKey) ||
          RivTypeKeys.interpolatorTypeKeys.contains(typeKey)) {
        block.add(document.objects[i]);
      } else {
        break;
      }
    }
    return block;
  }

  static RivRawObject _cloneObject(RivRawObject source) {
    return RivRawObject(
      typeKey: source.typeKey,
      properties: [
        for (final property in source.properties)
          RivRawProperty(
            key: property.key,
            fieldType: property.fieldType,
            valueBytes: Uint8List.fromList(property.valueBytes),
          ),
      ],
    );
  }

  static void _appendCopySuffix(RivRawObject object) {
    final property = object.property(RivPropertyKeys.componentName);
    final currentName = property == null
        ? ''
        : _decodeString(property.valueBytes);
    final encoded = (RivBinaryWriter()
          ..writeBytes(Uint8List.fromList('$currentName copy'.trim().codeUnits)))
        .takeBytes();
    if (property != null) {
      property.valueBytes = encoded;
    } else {
      object.properties.insert(
        0,
        RivRawProperty(
          key: RivPropertyKeys.componentName,
          fieldType: RivFieldType.string,
          valueBytes: encoded,
        ),
      );
    }
  }

  static List<int> _decodeVarUintList(Uint8List lengthPrefixed) {
    final reader = RivBinaryReader(lengthPrefixed);
    final byteLength = reader.readVarUint();
    final end = reader.position + byteLength;
    final values = <int>[];
    while (reader.position < end) {
      values.add(reader.readVarUint());
    }
    return values;
  }

  static Uint8List _encodeVarUintList(List<int> values) {
    final body = RivBinaryWriter();
    for (final value in values) {
      body.writeVarUint(value);
    }
    final bodyBytes = body.takeBytes();
    return (RivBinaryWriter()..writeBytes(bodyBytes)).takeBytes();
  }

  static String _decodeString(Uint8List lengthPrefixed) {
    final reader = RivBinaryReader(lengthPrefixed);
    final length = reader.readVarUint();
    return String.fromCharCodes(
      lengthPrefixed.sublist(reader.position, reader.position + length),
    );
  }
}

/// How references should be redirected during commit.
class _ReferencePlan {
  _ReferencePlan._({
    this.deleted = const {},
    Map<RivRawObject, RivRawObject> identityRedirects = const {},
    Map<RivRawProperty, RivRawObject> propertyOverrides = const {},
  }) : _identityRedirects = identityRedirects,
       _propertyOverrides = propertyOverrides;

  factory _ReferencePlan.forDelete(Set<RivRawObject> deleted) =>
      _ReferencePlan._(deleted: deleted);

  /// Reparent: the moved root's parent link must point at the new parent
  /// regardless of what it referenced before.
  factory _ReferencePlan.forReparent(
    RivRawObject movedRoot,
    RivRawObject newParent,
  ) {
    final parentProperty = movedRoot.property(
      RivPropertyKeys.componentParentId,
    );
    return _ReferencePlan._(
      propertyOverrides: parentProperty == null
          ? const {}
          : {parentProperty: newParent},
    );
  }

  /// Duplicate: clone-internal references point at sibling clones, the
  /// clone root parents onto the original's parent, and clone-external
  /// references resolve like the originals they were copied from.
  factory _ReferencePlan.forDuplicate({
    required _Span span,
    required Map<RivRawObject, RivRawObject> cloneByOriginal,
    required RivRawObject? cloneRootParent,
    required RivRawObject cloneRoot,
  }) {
    final overrides = <RivRawProperty, RivRawObject>{};
    cloneByOriginal.forEach((original, clone) {
      for (var i = 0; i < original.properties.length; i++) {
        final sourceProperty = original.properties[i];
        final cloneProperty = clone.properties[i];
        if (!RivComponentRefs.uintReferenceKeys.contains(sourceProperty.key) ||
            sourceProperty.fieldType != RivFieldType.uint) {
          continue;
        }
        final target = span.componentAt(sourceProperty.uintValue);
        if (target == null) continue;
        overrides[cloneProperty] = cloneByOriginal[target] ?? target;
      }
    });
    final rootParentProperty = cloneRoot.property(
      RivPropertyKeys.componentParentId,
    );
    if (rootParentProperty != null && cloneRootParent != null) {
      overrides[rootParentProperty] = cloneRootParent;
    }
    return _ReferencePlan._(propertyOverrides: overrides);
  }

  final Set<RivRawObject> deleted;
  final Map<RivRawObject, RivRawObject> _identityRedirects;
  final Map<RivRawProperty, RivRawObject> _propertyOverrides;

  /// The object identity that [property] of [owner] should reference
  /// after the operation, or `null` when it is not a reference.
  RivRawObject? redirect(
    RivRawObject owner,
    RivRawProperty property,
    _ResolvedReferences resolved,
  ) {
    final override = _propertyOverrides[property];
    if (override != null) return override;
    final original = resolved.singles[property];
    if (original == null) return null;
    return _identityRedirects[original] ?? original;
  }
}

class _ResolvedReferences {
  const _ResolvedReferences(this.singles, this.lists);

  final Map<RivRawProperty, RivRawObject> singles;
  final Map<RivRawProperty, List<RivRawObject>> lists;
}

/// One artboard's slice of the document object stream.
class _Span {
  _Span._(this._document, this.start, this.end);

  final RivRawDocument _document;

  /// Raw index of the artboard object.
  final int start;

  /// Exclusive raw end index (next top-level object or end of file).
  final int end;

  static const Set<int> _topLevelTypes = {
    RivTypeKeys.artboard,
    RivTypeKeys.backboard,
    RivTypeKeys.imageAsset,
    RivTypeKeys.fontAsset,
    RivTypeKeys.audioAsset,
    RivTypeKeys.fileAssetContents,
  };

  static _Span? of(RivRawDocument document, int artboardOrdinal) {
    var seen = -1;
    for (var i = 0; i < document.objects.length; i++) {
      if (document.objects[i].typeKey != RivTypeKeys.artboard) continue;
      seen++;
      if (seen != artboardOrdinal) continue;

      var end = i + 1;
      while (end < document.objects.length &&
          !_topLevelTypes.contains(document.objects[end].typeKey)) {
        end++;
      }
      return _Span._(document, i, end);
    }
    return null;
  }

  Iterable<RivRawObject> get allObjects =>
      _document.objects.getRange(start, end);

  bool isComponent(RivRawObject object) =>
      !RivTypeKeys.animationTypeKeys.contains(object.typeKey) ||
      RivTypeKeys.interpolatorTypeKeys.contains(object.typeKey);

  List<RivRawObject> get components => [
    for (final object in allObjects)
      if (isComponent(object)) object,
  ];

  RivRawObject? componentAt(int componentIndex) {
    final all = components;
    return componentIndex >= 0 && componentIndex < all.length
        ? all[componentIndex]
        : null;
  }

  int indexOfComponent(RivRawObject object) => components.indexOf(object);

  int? parentIndexOf(int componentIndex) {
    if (componentIndex == 0) return null;
    final object = componentAt(componentIndex);
    final property = object?.property(RivPropertyKeys.componentParentId);
    if (property == null || property.fieldType != RivFieldType.uint) return 0;
    return property.uintValue;
  }

  RivRawObject? parentObjectOf(int componentIndex) {
    final parentIndex = parentIndexOf(componentIndex);
    return parentIndex == null ? null : componentAt(parentIndex);
  }

  /// Component indices of [rootIndex] plus all its descendants.
  Set<int> subtreeOf(int rootIndex) {
    final all = components;
    final childrenOf = <int, List<int>>{};
    for (var i = 1; i < all.length; i++) {
      final parent = parentIndexOf(i);
      if (parent != null) childrenOf.putIfAbsent(parent, () => []).add(i);
    }
    final result = <int>{};
    final queue = [rootIndex];
    while (queue.isNotEmpty) {
      final index = queue.removeLast();
      if (!result.add(index)) continue;
      queue.addAll(childrenOf[index] ?? const []);
    }
    return result;
  }

  /// Raw objects backing [componentIndices], in stream order.
  List<RivRawObject> rawObjectsOfComponents(Set<int> componentIndices) {
    final all = components;
    final wanted = {for (final index in componentIndices) all[index]};
    return [
      for (final object in allObjects)
        if (wanted.contains(object)) object,
    ];
  }

  /// The last raw object of [componentIndex]'s subtree, ignoring
  /// components in [exclude] (used while planning a move).
  RivRawObject lastRawObjectOfSubtree(
    int componentIndex, {
    Set<int> exclude = const {},
  }) {
    final subtree = subtreeOf(componentIndex).difference(exclude);
    final objects = rawObjectsOfComponents(subtree);
    return objects.isNotEmpty ? objects.last : componentAt(componentIndex)!;
  }
}
