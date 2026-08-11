import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_document_model.dart';
import '../../../shared/widgets/editor_context_menu.dart';

/// Scrollable list of keyframe tracks for the selected animation.
///
/// Each keyed object renders a header row followed by one row per
/// animated property, with diamonds marking keyframe positions.
/// Diamonds can be dragged horizontally to retime keyframes when
/// [onRetimeKeyframe] is provided.
class KeyframeTrackList extends StatelessWidget {
  const KeyframeTrackList({
    super.key,
    required this.animation,
    required this.labelWidth,
    this.selectedKeyedObject,
    this.onSelectKeyedObject,
    this.onRetimeKeyframe,
    this.onDeleteKeyframe,
    this.onCopyKeyframe,
    this.onPasteKeyframe,
    this.canPaste = false,
  });

  final RivAnimationModel animation;

  /// Currently selected keyed object, highlighted in the list.
  final RivKeyedObjectModel? selectedKeyedObject;

  /// Invoked when a keyed-object header row is tapped.
  final ValueChanged<RivKeyedObjectModel>? onSelectKeyedObject;

  /// Invoked when a keyframe diamond is dropped at a new frame.
  /// When `null` the tracks are read-only.
  final void Function(RivKeyFrameModel keyframe, int newFrame)?
  onRetimeKeyframe;

  /// Invoked when the user chooses Delete from a keyframe's context
  /// menu. When `null`, keyframes cannot be deleted.
  final ValueChanged<RivKeyFrameModel>? onDeleteKeyframe;

  /// Invoked when the user copies a keyframe (receives the owning
  /// object, its property, and the keyframe).
  final void Function(
    RivKeyedObjectModel keyedObject,
    RivKeyedPropertyModel property,
    RivKeyFrameModel keyframe,
  )?
  onCopyKeyframe;

  /// Invoked when the user pastes the copied keyframe at the playhead.
  final VoidCallback? onPasteKeyframe;

  /// Whether the keyframe clipboard has content (enables Paste).
  final bool canPaste;

  /// Width reserved on the left for track names, so keyframe positions
  /// align with the shared time ruler above.
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    if (animation.keyedObjects.isEmpty) {
      return const Center(
        child: Text(
          'No keyframes in this animation',
          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
        ),
      );
    }
    return ListView(
      children: [
        for (final keyedObject in animation.keyedObjects) ...[
          _ObjectHeaderRow(
            name: keyedObject.objectName,
            selected: identical(keyedObject, selectedKeyedObject),
            onTap: () => onSelectKeyedObject?.call(keyedObject),
          ),
          for (final property in keyedObject.properties)
            _PropertyTrackRow(
              property: property,
              animation: animation,
              labelWidth: labelWidth,
              onRetimeKeyframe: onRetimeKeyframe,
              onDeleteKeyframe: onDeleteKeyframe,
              onCopyKeyframe: onCopyKeyframe == null
                  ? null
                  : (keyframe) =>
                        onCopyKeyframe!(keyedObject, property, keyframe),
              onPasteKeyframe: canPaste ? onPasteKeyframe : null,
            ),
        ],
      ],
    );
  }
}

class _ObjectHeaderRow extends StatelessWidget {
  const _ObjectHeaderRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 22,
        color: selected
            ? EditorTheme.accent.withValues(alpha: 0.18)
            : EditorTheme.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              Icons.widgets_outlined,
              size: 12,
              color: selected ? EditorTheme.accent : EditorTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: EditorTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyTrackRow extends StatelessWidget {
  const _PropertyTrackRow({
    required this.property,
    required this.animation,
    required this.labelWidth,
    required this.onRetimeKeyframe,
    required this.onDeleteKeyframe,
    required this.onCopyKeyframe,
    required this.onPasteKeyframe,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;
  final double labelWidth;
  final void Function(RivKeyFrameModel keyframe, int newFrame)?
  onRetimeKeyframe;
  final ValueChanged<RivKeyFrameModel>? onDeleteKeyframe;
  final ValueChanged<RivKeyFrameModel>? onCopyKeyframe;
  final VoidCallback? onPasteKeyframe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                property.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _KeyframeTrackArea(
              property: property,
              durationFrames: animation.durationFrames,
              onRetimeKeyframe: onRetimeKeyframe,
              onDeleteKeyframe: onDeleteKeyframe,
              onCopyKeyframe: onCopyKeyframe,
              onPasteKeyframe: onPasteKeyframe,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive keyframe strip: renders diamonds and handles dragging
/// them to new frames with a ghost preview.
class _KeyframeTrackArea extends StatefulWidget {
  const _KeyframeTrackArea({
    required this.property,
    required this.durationFrames,
    required this.onRetimeKeyframe,
    required this.onDeleteKeyframe,
    required this.onCopyKeyframe,
    required this.onPasteKeyframe,
  });

  final RivKeyedPropertyModel property;
  final int durationFrames;
  final void Function(RivKeyFrameModel keyframe, int newFrame)?
  onRetimeKeyframe;
  final ValueChanged<RivKeyFrameModel>? onDeleteKeyframe;
  final ValueChanged<RivKeyFrameModel>? onCopyKeyframe;
  final VoidCallback? onPasteKeyframe;

  @override
  State<_KeyframeTrackArea> createState() => _KeyframeTrackAreaState();
}

class _KeyframeTrackAreaState extends State<_KeyframeTrackArea> {
  static const double _hitRadius = 6;

  RivKeyFrameModel? _dragging;
  int? _ghostFrame;

  int _frameAt(double dx, double width) {
    if (widget.durationFrames <= 0 || width <= 0) return 0;
    return ((dx / width) * widget.durationFrames).round().clamp(
      0,
      widget.durationFrames,
    );
  }

  RivKeyFrameModel? _hitTest(double dx, double width) {
    if (widget.durationFrames <= 0) return null;
    RivKeyFrameModel? closest;
    var closestDistance = double.infinity;
    for (final keyframe in widget.property.keyframes) {
      if (keyframe.rawObjectIndex < 0) continue;
      final x = (keyframe.frame / widget.durationFrames) * width;
      final distance = (x - dx).abs();
      if (distance < _hitRadius && distance < closestDistance) {
        closest = keyframe;
        closestDistance = distance;
      }
    }
    return closest;
  }

  Future<void> _showKeyframeMenu(
    Offset localPosition,
    Offset globalPosition,
    double width,
  ) async {
    final hit = _hitTest(localPosition.dx, width);
    final entries = <ContextMenuEntry<String>>[
      if (hit != null && widget.onCopyKeyframe != null)
        const ContextMenuEntry(
          value: 'copy',
          label: 'Copy keyframe',
          icon: Icons.copy_outlined,
        ),
      if (widget.onPasteKeyframe != null)
        const ContextMenuEntry(
          value: 'paste',
          label: 'Paste at playhead',
          icon: Icons.content_paste_outlined,
        ),
      if (hit != null && widget.onDeleteKeyframe != null)
        const ContextMenuEntry(
          value: 'delete',
          label: 'Delete keyframe',
          icon: Icons.delete_outline,
          destructive: true,
          dividerBefore: true,
        ),
    ];
    if (entries.isEmpty) return;
    final action = await showEditorContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
    );
    switch (action) {
      case 'copy':
        widget.onCopyKeyframe?.call(hit!);
      case 'paste':
        widget.onPasteKeyframe?.call();
      case 'delete':
        widget.onDeleteKeyframe?.call(hit!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onRetimeKeyframe != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp:
              (widget.onDeleteKeyframe == null &&
                  widget.onCopyKeyframe == null &&
                  widget.onPasteKeyframe == null)
              ? null
              : (details) => _showKeyframeMenu(
                  details.localPosition,
                  details.globalPosition,
                  width,
                ),
          onHorizontalDragStart: editable
              ? (details) {
                  final hit = _hitTest(details.localPosition.dx, width);
                  if (hit == null) return;
                  setState(() {
                    _dragging = hit;
                    _ghostFrame = hit.frame;
                  });
                }
              : null,
          onHorizontalDragUpdate: editable
              ? (details) {
                  if (_dragging == null) return;
                  setState(() {
                    _ghostFrame = _frameAt(details.localPosition.dx, width);
                  });
                }
              : null,
          onHorizontalDragEnd: editable
              ? (details) {
                  final dragging = _dragging;
                  final ghostFrame = _ghostFrame;
                  if (dragging != null &&
                      ghostFrame != null &&
                      ghostFrame != dragging.frame) {
                    widget.onRetimeKeyframe!(dragging, ghostFrame);
                  }
                  setState(() {
                    _dragging = null;
                    _ghostFrame = null;
                  });
                }
              : null,
          onHorizontalDragCancel: editable
              ? () => setState(() {
                  _dragging = null;
                  _ghostFrame = null;
                })
              : null,
          child: MouseRegion(
            cursor: editable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: CustomPaint(
              size: const Size.fromHeight(20),
              painter: _KeyframeRowPainter(
                property: widget.property,
                durationFrames: widget.durationFrames,
                draggingKeyframe: _dragging,
                ghostFrame: _ghostFrame,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints keyframe diamonds along a track row, plus an optional ghost
/// diamond while one is being dragged.
class _KeyframeRowPainter extends CustomPainter {
  _KeyframeRowPainter({
    required this.property,
    required this.durationFrames,
    this.draggingKeyframe,
    this.ghostFrame,
  });

  final RivKeyedPropertyModel property;
  final int durationFrames;
  final RivKeyFrameModel? draggingKeyframe;
  final int? ghostFrame;

  static const double _diamondRadius = 3.5;

  void _drawDiamond(Canvas canvas, double x, double y, Paint paint) {
    final path = Path()
      ..moveTo(x, y - _diamondRadius)
      ..lineTo(x + _diamondRadius, y)
      ..lineTo(x, y + _diamondRadius)
      ..lineTo(x - _diamondRadius, y)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = EditorTheme.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      linePaint,
    );

    if (durationFrames <= 0) return;
    final y = size.height / 2;
    final diamondPaint = Paint()..color = EditorTheme.accent;
    final dimmedPaint = Paint()
      ..color = EditorTheme.accent.withValues(alpha: 0.35);

    for (final keyframe in property.keyframes) {
      final x = (keyframe.frame / durationFrames) * size.width;
      final isDragged = identical(keyframe, draggingKeyframe);
      _drawDiamond(canvas, x, y, isDragged ? dimmedPaint : diamondPaint);
    }

    // Ghost diamond at the drop position.
    final ghost = ghostFrame;
    if (ghost != null) {
      final x = (ghost / durationFrames) * size.width;
      _drawDiamond(canvas, x, y, Paint()..color = EditorTheme.playhead);
    }
  }

  @override
  bool shouldRepaint(_KeyframeRowPainter oldDelegate) =>
      oldDelegate.property != property ||
      oldDelegate.durationFrames != durationFrames ||
      oldDelegate.draggingKeyframe != draggingKeyframe ||
      oldDelegate.ghostFrame != ghostFrame;
}
