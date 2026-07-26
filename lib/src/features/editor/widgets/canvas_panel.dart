import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../../core/commands/editor_command.dart';
import '../../../core/services/scene_hit_tester.dart';
import '../../../core/services/selection_service.dart';
import '../../../core/services/view_transform.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../core/tools/editor_tool.dart';
import '../../../core/tools/tool_controller.dart';
import '../../../core/model/scene_node_ref.dart';
import '../../../riv/riv_format.dart';
import '../../../riv/riv_hierarchy.dart';
import '../../../riv/riv_hit_regions.dart';
import '../../../riv/riv_shape_paints.dart';
import '../state/editor_state.dart';

/// Center canvas composed of the three layers required by §2.3:
/// content (Rive render), overlay (tool drawings, grid), and
/// interaction (pointer routing to the active tool).
///
/// The [ViewTransform] lives in a [ValueNotifier] consumed by the
/// layers in their *paint* phase: pan/zoom never rebuilds the widget
/// tree, keeping the hot path at one repaint per changed layer.
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
  final ValueNotifier<ViewTransform> _transform = ValueNotifier(
    const ViewTransform(),
  );

  /// Bumped to invalidate only the overlay layer (§2.3 acceptance:
  /// overlay never repaints because content changed, and vice versa).
  final ValueNotifier<int> _overlayEpoch = ValueNotifier(0);

  /// Identity of the last-fitted view: (documentSessionId, artboard
  /// ordinal). Engine reloads after edits create new artboard objects
  /// for the *same* logical artboard, so object identity would refit
  /// (and yank the user's zoom) on every edit; this pair is stable
  /// across edits and changes only on real navigation.
  (int, int)? _fittedViewIdentity;

  /// The transform produced by the most recent auto-fit. While the
  /// current transform still equals it (user hasn't panned/zoomed),
  /// viewport size changes re-fit; the moment the user touches the
  /// view, resizes leave it alone.
  ViewTransform? _lastAutoFit;
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();
    widget.toolController.attachContext(this);
    // Selection outlines and tool previews are drawn on the overlay
    // from document + selection state, so both must invalidate it:
    // without this, outlines freeze at their old position after a
    // move/edit while the content layer shows the new state.
    widget.state.addListener(_invalidateOverlay);
    widget.state.selection.addListener(_invalidateOverlay);
  }

  void _invalidateOverlay() => _overlayEpoch.value++;

  @override
  void dispose() {
    widget.state.removeListener(_invalidateOverlay);
    widget.state.selection.removeListener(_invalidateOverlay);
    widget.toolController.attachContext(null);
    _transform.dispose();
    _overlayEpoch.dispose();
    super.dispose();
  }

  // -- ToolContext ---------------------------------------------------------

  @override
  ViewTransform get viewTransform => _transform.value;

  @override
  void setViewTransform(ViewTransform transform) {
    _transform.value = transform;
  }

  @override
  void requestOverlayRepaint() {
    _overlayEpoch.value++;
  }

  @override
  int get activeArtboardOrdinal => widget.state.activeArtboardOrdinal;

  @override
  void dispatch(EditorCommand command) {
    widget.state.dispatch(command);
  }

  SceneHitTester? _hitTester;
  int _hitTesterDocumentRevision = -1;
  int _hitTesterArtboardOrdinal = -1;

  /// Rebuilt only when the document or active artboard changes, never
  /// per pointer event (§2.3: no per-event scene scans). Keyed on the
  /// synchronous [EditorState.documentRevision] (bumped before the
  /// async engine reload) so regions always match the raw bytes a tool
  /// just mutated.
  @override
  SceneHitTester get hitTester {
    final raw = widget.state.document?.editor?.raw;
    final ordinal = widget.state.activeArtboardOrdinal;
    final revision = widget.state.documentRevision;
    if (raw == null || ordinal < 0) return SceneHitTester(const []);
    if (_hitTester == null ||
        _hitTesterDocumentRevision != revision ||
        _hitTesterArtboardOrdinal != ordinal) {
      _hitTester = SceneHitTester(
        RivHitRegions.forArtboard(
          raw,
          ordinal,
          resolveDrawableBounds: _engineDrawableBounds,
        ),
      );
      _hitTesterDocumentRevision = revision;
      _hitTesterArtboardOrdinal = ordinal;
    }
    return _hitTester!;
  }

  /// Bounds for engine-measured drawables (text): asks the live
  /// artboard for the component's shaped world bounds. Falls back to a
  /// small square at the node's position so freshly created text is
  /// selectable even before the engine reload lands.
  Rect? _engineDrawableBounds(RivHierarchyNode node, Offset translation) {
    const fallbackExtent = 40.0;
    final artboard = widget.state.activeArtboard;
    final component = node.name.isEmpty ? null : artboard?.component(node.name);
    if (component == null) {
      return Rect.fromCenter(
        center: translation,
        width: fallbackExtent,
        height: fallbackExtent,
      );
    }
    final local = component.localBounds;
    final world = local.transform(component.worldTransform);
    if (world.width <= 0 || world.height <= 0) {
      return Rect.fromCenter(
        center: translation,
        width: fallbackExtent,
        height: fallbackExtent,
      );
    }
    return Rect.fromLTRB(world.left, world.top, world.right, world.bottom);
  }

  @override
  SelectionService get selection => widget.state.selection;

  @override
  RivPaintTarget? fillPaintOf(SceneNodeRef ref) {
    final raw = widget.state.document?.editor?.raw;
    if (raw == null) return null;
    return RivShapePaints.fillOf(raw, ref.artboardOrdinal, ref.componentIndex);
  }

  @override
  Offset? componentTranslation(SceneNodeRef ref) {
    final raw = widget.state.document?.editor?.raw;
    if (raw == null) return null;
    final object = RivHierarchy.componentObjectAt(
      raw,
      ref.artboardOrdinal,
      ref.componentIndex,
    );
    if (object == null) return null;
    final x = object.property(RivPropertyKeys.nodeX);
    final y = object.property(RivPropertyKeys.nodeY);
    return Offset(
      x != null && x.fieldType == RivFieldType.float ? x.floatValue : 0,
      y != null && y.fieldType == RivFieldType.float ? y.floatValue : 0,
    );
  }

  // -- Interaction ---------------------------------------------------------

  ToolPointerEvent _toolEvent(PointerEvent event) => ToolPointerEvent(
    viewPosition: event.localPosition,
    scenePosition: _transform.value.viewToScene(event.localPosition),
    isSecondary: event.buttons == 2,
    isToggleModifierPressed:
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed,
    isRangeModifierPressed: HardwareKeyboard.instance.isShiftPressed,
  );

  void _zoomTo(double scale) {
    final size = context.size;
    if (size == null) return;
    setViewTransform(
      _transform.value.zoomedBy(
        scale / _transform.value.scale,
        viewAnchor: Offset(size.width / 2, size.height / 2),
      ),
    );
  }

  void _resetView() {
    final artboard = widget.state.activeArtboard;
    final size = context.size;
    if (artboard == null || size == null) {
      _transform.value = const ViewTransform();
      return;
    }
    setViewTransform(
      ViewTransform.fit(
        Size(artboard.bounds.width, artboard.bounds.height),
        size,
      ),
    );
  }

  /// Fits the view to [artboard] once per (document, artboard ordinal),
  /// after the first frame in which it appears (viewport size is known
  /// then). Edits reload the engine but keep the same identity, so the
  /// user's zoom and pan survive editing.
  void _fitOnArtboardChange(rive.Artboard? artboard, Size viewportSize) {
    if (artboard == null) return;
    final identity = (
      widget.state.documentSessionId,
      widget.state.activeArtboardOrdinal,
    );
    final isNewView = identity != _fittedViewIdentity;
    // Windows can finish sizing after the first fit. While the view is
    // still exactly the auto-fit result (user hasn't panned or zoomed),
    // follow viewport size changes with a fresh fit; once the user
    // touches the view, resizes leave it alone.
    final viewportChanged =
        _lastViewportSize != null && _lastViewportSize != viewportSize;
    final untouched = _transform.value == _lastAutoFit;
    _lastViewportSize = viewportSize;
    if (!isNewView && !(viewportChanged && untouched)) return;
    _fittedViewIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Use the live viewport size: the constraints captured during the
      // first build can predate window sizing and produce a bogus fit.
      final size = context.size ?? viewportSize;
      final fitted = ViewTransform.fit(
        Size(artboard.bounds.width, artboard.bounds.height),
        size,
      );
      _lastAutoFit = fitted;
      setViewTransform(fitted);
    });
  }

  @override
  Widget build(BuildContext context) {
    final artboard = widget.state.activeArtboard;
    // Rebuilds when the active tool changes so pointer routing, cursor,
    // and the overlay painter always reference the current tool.
    return ListenableBuilder(
      listenable: widget.toolController,
      builder: (context, _) {
        final tool = widget.toolController.activeTool;
        return LayoutBuilder(
          builder: (context, constraints) {
            _fitOnArtboardChange(artboard, constraints.biggest);
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: (event) =>
                        tool?.onPointerDown(this, _toolEvent(event)),
                    onPointerMove: (event) =>
                        tool?.onPointerMove(this, _toolEvent(event)),
                    onPointerUp: (event) =>
                        tool?.onPointerUp(this, _toolEvent(event)),
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
                        setViewTransform(
                          _transform.value.zoomedBy(
                            factor,
                            viewAnchor: event.localPosition,
                          ),
                        );
                      }
                    },
                    child: MouseRegion(
                      cursor: tool?.cursor ?? MouseCursor.defer,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: _GridPainter(transform: _transform),
                            ),
                          ),
                          if (artboard != null)
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: _ArtboardFramePainter(
                                  transform: _transform,
                                  name: artboard.name,
                                  size: Size(
                                    artboard.bounds.width,
                                    artboard.bounds.height,
                                  ),
                                ),
                              ),
                            ),
                          if (artboard != null)
                            RepaintBoundary(
                              child: ClipRect(
                                child: _TransformedContent(
                                  transform: _transform,
                                  // Anchored at scene (0,0) and sized
                                  // exactly to the artboard: artboard
                                  // coordinates ARE scene coordinates,
                                  // so hit regions and overlays align
                                  // with the rendered content (§2.3).
                                  // Align loosens the Stack's tight
                                  // constraints so the SizedBox holds.
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                      width: artboard.bounds.width,
                                      height: artboard.bounds.height,
                                      child: rive.RiveArtboardWidget(
                                        artboard: artboard,
                                        painter: widget.state.painter,
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
                                  epoch: _overlayEpoch,
                                  transform: _transform,
                                  tool: tool,
                                  toolContext: this,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: ValueListenableBuilder(
                    valueListenable: _transform,
                    builder: (context, transform, _) => _ZoomControls(
                      scale: transform.scale,
                      onZoomTo: _zoomTo,
                      onReset: _resetView,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Applies the view transform to [child] without rebuilding it.
///
/// [AnimatedBuilder] passes the pre-built child through, so pan/zoom
/// only updates the transform layer; the Rive subtree is untouched.
class _TransformedContent extends StatelessWidget {
  const _TransformedContent({required this.transform, required this.child});

  final ValueListenable<ViewTransform> transform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transform,
      child: child,
      builder: (context, prebuiltChild) {
        final value = transform.value;
        return Transform(
          transform: Matrix4.identity()
            ..translateByDouble(value.offset.dx, value.offset.dy, 0, 1)
            ..scaleByDouble(value.scale, value.scale, 1, 1),
          child: prebuiltChild,
        );
      },
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
///
/// Repaints when the overlay epoch changes; widget rebuilds are not
/// involved.
class _ToolOverlayPainter extends CustomPainter {
  _ToolOverlayPainter({
    required this.epoch,
    required this.transform,
    required this.tool,
    required this.toolContext,
  }) : super(repaint: Listenable.merge([epoch, transform]));

  final ValueListenable<int> epoch;

  /// Selection outlines are projected to view space at paint time, so
  /// pan/zoom must repaint the overlay or outlines detach from shapes.
  final ValueListenable<ViewTransform> transform;

  final EditorTool? tool;
  final ToolContext toolContext;

  @override
  void paint(Canvas canvas, Size size) {
    tool?.paintOverlay(canvas, size, toolContext);
  }

  @override
  bool shouldRepaint(_ToolOverlayPainter oldDelegate) =>
      oldDelegate.tool != tool;
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

/// Figma-style artboard frame: a surface-coloured plate, border, and
/// name label so the frame is always visible even when the artboard
/// itself is transparent. Painted under the Rive content; the engine
/// draws any authored artboard background on top.
class _ArtboardFramePainter extends CustomPainter {
  _ArtboardFramePainter({
    required this.transform,
    required this.name,
    required this.size,
  }) : super(repaint: transform);

  final ValueListenable<ViewTransform> transform;
  final String name;
  final Size size;

  static const double _labelPadding = 6;

  @override
  void paint(Canvas canvas, Size viewSize) {
    final value = transform.value;
    final rect = Rect.fromPoints(
      value.sceneToView(Offset.zero),
      value.sceneToView(Offset(size.width, size.height)),
    );

    canvas.drawRect(rect, Paint()..color = EditorTheme.surface);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.border,
    );

    // Name label above the top-left corner, fixed size regardless of
    // zoom (view-space text, like Figma frame titles).
    final painter = TextPainter(
      text: TextSpan(
        text: '$name  ${size.width.round()} × ${size.height.round()}',
        style: const TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(rect.left, rect.top - painter.height - _labelPadding),
    );
  }

  @override
  bool shouldRepaint(_ArtboardFramePainter oldDelegate) =>
      oldDelegate.name != name || oldDelegate.size != size;
}

/// Dotted background grid that follows the view transform.
///
/// All dots are emitted in a single [Canvas.drawRawPoints] call; cost
/// is one canvas op regardless of dot count. Repaints via the
/// transform listenable, never through widget rebuilds.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.transform}) : super(repaint: transform);

  final ValueListenable<ViewTransform> transform;

  static const double _baseSpacing = 24;
  static const double _minSpacing = 12;
  static const double _maxSpacing = 48;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.viewportBackground,
    );

    final value = transform.value;
    var spacing = _baseSpacing * value.scale;
    while (spacing < _minSpacing) {
      spacing *= 2;
    }
    while (spacing > _maxSpacing) {
      spacing /= 2;
    }

    final startX = value.offset.dx % spacing;
    final startY = value.offset.dy % spacing;
    final columns = ((size.width - startX) / spacing).ceil() + 1;
    final rows = ((size.height - startY) / spacing).ceil() + 1;
    if (columns <= 0 || rows <= 0) return;

    final points = Float32List(columns * rows * 2);
    var i = 0;
    for (var column = 0; column < columns; column++) {
      final x = startX + column * spacing;
      for (var row = 0; row < rows; row++) {
        points[i++] = x;
        points[i++] = startY + row * spacing;
      }
    }
    canvas.drawRawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = EditorTheme.border.withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}
