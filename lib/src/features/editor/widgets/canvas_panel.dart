import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../core/services/view_transform.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../core/tools/editor_tool.dart';
import '../../../core/tools/tool_controller.dart';
import '../state/editor_state.dart';

/// Center canvas composed of the three layers required by §2.3:
/// content (Rive render), overlay (tool drawings, grid), and
/// interaction (pointer routing to the active tool).
///
/// The [ViewTransform] is the single source of truth consumed by all
/// three layers.
class CanvasPanel extends StatefulWidget {
  const CanvasPanel({
    super.key,
    required this.state,
    required this.toolController,
  });

  final EditorState state;
  final ToolController toolController;

  @override
  State<CanvasPanel> createState() => _CanvasPanelState();
}

class _CanvasPanelState extends State<CanvasPanel> implements ToolContext {
  ViewTransform _transform = const ViewTransform();

  /// Bumped to invalidate only the overlay layer (§2.3 acceptance:
  /// overlay never repaints because content changed, and vice versa).
  int _overlayEpoch = 0;

  @override
  void initState() {
    super.initState();
    widget.toolController.attachContext(this);
  }

  @override
  void dispose() {
    widget.toolController.attachContext(null);
    super.dispose();
  }

  // -- ToolContext ---------------------------------------------------------

  @override
  ViewTransform get viewTransform => _transform;

  @override
  void setViewTransform(ViewTransform transform) {
    setState(() => _transform = transform);
  }

  @override
  void requestOverlayRepaint() {
    setState(() => _overlayEpoch++);
  }

  // -- Interaction ---------------------------------------------------------

  ToolPointerEvent _toolEvent(PointerEvent event) => ToolPointerEvent(
    viewPosition: event.localPosition,
    scenePosition: _transform.viewToScene(event.localPosition),
    isSecondary: event.buttons == 2,
  );

  void _zoomTo(double scale) {
    final size = context.size;
    if (size == null) return;
    setViewTransform(
      _transform.zoomedBy(
        scale / _transform.scale,
        viewAnchor: Offset(size.width / 2, size.height / 2),
      ),
    );
  }

  void _resetView() => setViewTransform(const ViewTransform());

  @override
  Widget build(BuildContext context) {
    final artboard = widget.state.activeArtboard;
    final tool = widget.toolController.activeTool;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: (event) =>
                tool?.onPointerDown(this, _toolEvent(event)),
            onPointerMove: (event) =>
                tool?.onPointerMove(this, _toolEvent(event)),
            onPointerUp: (event) => tool?.onPointerUp(this, _toolEvent(event)),
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
                setViewTransform(
                  _transform.zoomedBy(factor, viewAnchor: event.localPosition),
                );
              }
            },
            child: MouseRegion(
              cursor: tool?.cursor ?? MouseCursor.defer,
              child: _CanvasLayers(
                transform: _transform,
                overlayEpoch: _overlayEpoch,
                toolContext: this,
                tool: tool,
                artboard: artboard,
                painter: widget.state.painter,
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: _ZoomControls(
            scale: _transform.scale,
            onZoomTo: _zoomTo,
            onReset: _resetView,
          ),
        ),
      ],
    );
  }
}

/// Stacks the grid, content, and overlay paint layers.
class _CanvasLayers extends StatelessWidget {
  const _CanvasLayers({
    required this.transform,
    required this.overlayEpoch,
    required this.toolContext,
    required this.tool,
    required this.artboard,
    required this.painter,
  });

  final ViewTransform transform;
  final int overlayEpoch;
  final ToolContext toolContext;
  final EditorTool? tool;
  final rive.Artboard? artboard;
  final rive.ArtboardPainter painter;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _GridPainter(transform: transform)),
        ),
        if (artboard != null)
          RepaintBoundary(
            child: ClipRect(
              child: Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(
                    transform.offset.dx,
                    transform.offset.dy,
                    0,
                    1,
                  )
                  ..scaleByDouble(transform.scale, transform.scale, 1, 1),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: rive.RiveArtboardWidget(
                      artboard: artboard!,
                      painter: painter,
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const _EmptyCanvas(),
        RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ToolOverlayPainter(
                epoch: overlayEpoch,
                tool: tool,
                toolContext: toolContext,
              ),
            ),
          ),
        ),
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

/// Delegates overlay painting to the active tool (§2.3 layer 2).
class _ToolOverlayPainter extends CustomPainter {
  _ToolOverlayPainter({
    required this.epoch,
    required this.tool,
    required this.toolContext,
  });

  final int epoch;
  final EditorTool? tool;
  final ToolContext toolContext;

  @override
  void paint(Canvas canvas, Size size) {
    tool?.paintOverlay(canvas, size, toolContext);
  }

  @override
  bool shouldRepaint(_ToolOverlayPainter oldDelegate) =>
      oldDelegate.epoch != epoch || oldDelegate.tool != tool;
}

/// Zoom percentage readout plus zoom buttons.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.onZoomTo,
    required this.onReset,
  });

  final double scale;
  final ValueChanged<double> onZoomTo;
  final VoidCallback onReset;

  static const double _stepFactor = 1.25;

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
            onTap: () => onZoomTo(scale / _stepFactor),
          ),
          InkWell(
            onTap: onReset,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${(scale * 100).round()}%',
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
            onTap: () => onZoomTo(scale * _stepFactor),
          ),
          _ZoomButton(
            icon: Icons.fit_screen,
            tooltip: 'Reset view (100%)',
            onTap: onReset,
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

/// Dotted background grid that follows the view transform.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.transform});

  final ViewTransform transform;

  static const double _baseSpacing = 24;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.viewportBackground,
    );

    var spacing = _baseSpacing * transform.scale;
    while (spacing < 12) {
      spacing *= 2;
    }
    while (spacing > 48) {
      spacing /= 2;
    }

    final dotPaint = Paint()
      ..color = EditorTheme.border.withValues(alpha: 0.55);
    final startX = transform.offset.dx % spacing;
    final startY = transform.offset.dy % spacing;
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
