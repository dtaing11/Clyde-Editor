import 'package:flutter/material.dart';

import '../../../core/theme/editor_theme.dart';
import '../../../riv/riv_document_model.dart';

/// Scrollable list of keyframe tracks for the selected animation.
///
/// Each keyed object renders a header row followed by one row per
/// animated property, with diamonds marking keyframe positions.
class KeyframeTrackList extends StatelessWidget {
  const KeyframeTrackList({
    super.key,
    required this.animation,
    required this.labelWidth,
  });

  final RivAnimationModel animation;

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
          _ObjectHeaderRow(name: keyedObject.objectName),
          for (final property in keyedObject.properties)
            _PropertyTrackRow(
              property: property,
              animation: animation,
              labelWidth: labelWidth,
            ),
        ],
      ],
    );
  }
}

class _ObjectHeaderRow extends StatelessWidget {
  const _ObjectHeaderRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      color: EditorTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(
            Icons.widgets_outlined,
            size: 12,
            color: EditorTheme.textSecondary,
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
    );
  }
}

class _PropertyTrackRow extends StatelessWidget {
  const _PropertyTrackRow({
    required this.property,
    required this.animation,
    required this.labelWidth,
  });

  final RivKeyedPropertyModel property;
  final RivAnimationModel animation;
  final double labelWidth;

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
            child: CustomPaint(
              size: const Size.fromHeight(20),
              painter: _KeyframeRowPainter(
                property: property,
                durationFrames: animation.durationFrames,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints keyframe diamonds along a track row.
class _KeyframeRowPainter extends CustomPainter {
  _KeyframeRowPainter({required this.property, required this.durationFrames});

  final RivKeyedPropertyModel property;
  final int durationFrames;

  static const double _diamondRadius = 3.5;

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
    final diamondPaint = Paint()..color = EditorTheme.accent;
    for (final keyframe in property.keyframes) {
      final x = (keyframe.frame / durationFrames) * size.width;
      final y = size.height / 2;
      final path = Path()
        ..moveTo(x, y - _diamondRadius)
        ..lineTo(x + _diamondRadius, y)
        ..lineTo(x, y + _diamondRadius)
        ..lineTo(x - _diamondRadius, y)
        ..close();
      canvas.drawPath(path, diamondPaint);
    }
  }

  @override
  bool shouldRepaint(_KeyframeRowPainter oldDelegate) =>
      oldDelegate.property != property ||
      oldDelegate.durationFrames != durationFrames;
}
