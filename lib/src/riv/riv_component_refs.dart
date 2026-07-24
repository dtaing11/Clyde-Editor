/// Property keys whose uint value references a component index inside
/// the owning artboard's object list.
///
/// Compiled from rive-runtime v7 generated headers (`*_base.hpp`): every
/// `*IdPropertyKey` whose importer resolves through
/// `context->resolve(id)` against the artboard. Keys that reference
/// non-component index spaces (animations, state machine inputs, assets,
/// view models) are intentionally absent.
abstract final class RivComponentRefs {
  /// Single-value component references.
  static const Set<int> uintReferenceKeys = {
    5, // Component.parentId
    51, // KeyedObject.objectId
    69, // InterpolatingKeyFrame.interpolatorId
    92, // ClippingShape.sourceId
    95, // Tendon.boneId
    119, // DrawTarget.drawableId
    121, // DrawRules.drawTargetId
    173, // TargetedConstraint.targetId
    224, // StateMachineListener.targetId
    272, // TextValueRun.styleId
    296, // Solo.activeComponentId
    313, // Joystick.handleSourceId
    350, // StateTransition.interpolatorId
    378, // TextModifierRange.runId
    494, // TextStylePaint.styleId (TextStyle reference)
    591, // AdvanceableState.interpolatorId
    714, // TransitionValueCondition.interpolatorId
    725, // ScrollBarConstraint.scrollConstraintId
    726, // ScrollConstraint.physicsId
    731, // ScrollPhysics.constraintId
    758, // KeyFrameInterpolator chained interpolatorId
    977, // Newer keyed object reference
  };

  /// Keys encoding a *list* of ids as length-prefixed bytes. Their id
  /// space differs per owner (data-bind paths are not component
  /// indices), so structural operations that shift component indices
  /// must be refused when these are present rather than guessed at.
  static const Set<int> listReferenceKeys = {
    582, // DataBind.dataBindPathIds
    588, // TransformComponentConstraint.sourcePathIds
    711, // FollowPathConstraint.sourcePathIds
    866, // BindableProperty.dataBindPathIds
  };
}
