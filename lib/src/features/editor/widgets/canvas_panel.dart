import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../core/theme/editor_theme.dart';
import '../state/editor_state.dart';

/// Center canvas: renders the active artboard with the Rive Renderer
/// inside a pannable, zoomable workspace with a dotted grid.
class CanvasPanel extends StatefulWidget {
  const CanvasPanel({super.key, required this.state});

  final EditorState state;

  @override
  State<CanvasPanel> createState() => _CanvasPanelState();
}

class _CanvasPanelState extends State<CanvasPanel> {
  final TransformationController _transform = TransformationController();

  static const double _minScale = 0.1;
  static const double _maxScale = 8;

  double get _scale => _transform.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() => setState(() {});

  void _zoomTo(double scale) {
    final size = context.size;
    if (size == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final sceneCenter = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
  }

  void _resetView() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final artboard = widget.state.activeArtboard;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(transform: _transform.value),
            child: artboard == null
                ? const _EmptyCanvas()
                : InteractiveViewer(
                    transformationController: _transform,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: rive.RiveArtboardWidget(
                          artboard: artboard,
                          painter: widget.state.painter,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(right: 10, bottom: 10, child: _ZoomControls(this)),
      ],
    );
  }
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.animation, size: 48, color: EditorTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            'Open or create a document to start',
            style: TextStyle(color: EditorTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Zoom percentage readout plus fit/zoom buttons.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls(this.canvas);

  final _CanvasPanelState canvas;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorTheme.surfaceAlt.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onTap: () => canvas._zoomTo(
              (canvas._scale / 1.25).clamp(
                _CanvasPanelState._minScale,
                _CanvasPanelState._maxScale,
              ),
            ),
          ),
          InkWell(
            onTap: canvas._resetView,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${(canvas._scale * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: EditorTheme.textPrimary,
                ),
              ),
            ),
          ),
          _ZoomButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onTap: () => canvas._zoomTo(
              (canvas._scale * 1.25).clamp(
                _CanvasPanelState._minScale,
                _CanvasPanelState._maxScale,
              ),
            ),
          ),
          _ZoomButton(
            icon: Icons.fit_screen,
            tooltip: 'Reset view (100%)',
            onTap: canvas._resetView,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: EditorTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Dotted background grid that follows the canvas transform.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.transform});

  final Matrix4 transform;

  static const double _baseSpacing = 24;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.viewportBackground,
    );

    final scale = transform.getMaxScaleOnAxis();
    var spacing = _baseSpacing * scale;
    while (spacing < 12) {
      spacing *= 2;
    }
    while (spacing > 48) {
      spacing /= 2;
    }

    final origin = Offset(transform.storage[12], transform.storage[13]);
    final dotPaint = Paint()
      ..color = EditorTheme.border.withValues(alpha: 0.55);

    final startX = origin.dx % spacing;
    final startY = origin.dy % spacing;
    for (var x = startX; x < size.width; x += spacing) {
      for (var y = startY; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.transform != transform;
}
