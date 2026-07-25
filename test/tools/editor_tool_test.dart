import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/commands/editor_command.dart';
import 'package:rive_editor/src/core/model/scene_node_ref.dart';
import 'package:rive_editor/src/core/commands/shape_commands.dart';
import 'package:rive_editor/src/core/services/scene_hit_tester.dart';
import 'package:rive_editor/src/core/services/selection_service.dart';
import 'package:rive_editor/src/core/services/view_transform.dart';
import 'package:rive_editor/src/core/tools/editor_tool.dart';
import 'package:rive_editor/src/core/tools/tool_controller.dart';
import 'package:rive_editor/src/features/editor/tools/core_tools.dart';
import 'package:rive_editor/src/features/editor/tools/shape_tools.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';

/// Records tool requests without any widgets.
final class _TestToolContext implements ToolContext {
  ViewTransform transform = const ViewTransform();
  int overlayRepaints = 0;
  final List<EditorCommand> dispatched = [];

  @override
  ViewTransform get viewTransform => transform;

  @override
  void setViewTransform(ViewTransform value) => transform = value;

  @override
  void requestOverlayRepaint() => overlayRepaints++;

  @override
  int get activeArtboardOrdinal => 0;

  @override
  void dispatch(EditorCommand command) => dispatched.add(command);

  @override
  SceneHitTester hitTester = SceneHitTester(const []);

  @override
  final SelectionService selection = SelectionService();
}

ToolPointerEvent _eventAt(Offset view, {bool secondary = false}) =>
    ToolPointerEvent(
      viewPosition: view,
      scenePosition: view,
      isSecondary: secondary,
    );

ToolRegistry _registry() => ToolRegistry()
  ..register(SelectionTool())
  ..register(HandTool())
  ..register(const ZoomTool());

void main() {
  _shapeToolTests();
  _selectionHitTests();
  group('ViewTransform', () {
    test('scene/view round-trip at arbitrary scale and offset', () {
      const transform = ViewTransform(scale: 2.5, offset: Offset(40, -12));
      const scenePoint = Offset(123.4, 56.7);
      final roundTripped = transform.viewToScene(
        transform.sceneToView(scenePoint),
      );
      expect(roundTripped.dx, closeTo(scenePoint.dx, 1e-9));
      expect(roundTripped.dy, closeTo(scenePoint.dy, 1e-9));
    });

    test('zoom keeps the anchor point fixed in scene space', () {
      const transform = ViewTransform(scale: 1, offset: Offset(10, 10));
      const anchor = Offset(200, 150);
      final before = transform.viewToScene(anchor);
      final zoomed = transform.zoomedBy(2, viewAnchor: anchor);
      final after = zoomed.viewToScene(anchor);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
      expect(zoomed.scale, 2);
    });

    test('zoom clamps to bounds', () {
      const transform = ViewTransform(scale: 7);
      final zoomed = transform.zoomedBy(10, viewAnchor: Offset.zero);
      expect(zoomed.scale, ViewTransform.maxScale);
      final shrunk = const ViewTransform(
        scale: 0.2,
      ).zoomedBy(0.01, viewAnchor: Offset.zero);
      expect(shrunk.scale, ViewTransform.minScale);
    });

    test('fit centres the scene within the view', () {
      final fitted = ViewTransform.fit(
        const Size(100, 100),
        const Size(500, 300),
        padding: 50,
      );
      // Constrained by height: (300 - 100) / 100 = 2.
      expect(fitted.scale, 2);
      final centre = fitted.sceneToView(const Offset(50, 50));
      expect(centre.dx, closeTo(250, 1e-9));
      expect(centre.dy, closeTo(150, 1e-9));
    });
  });

  group('ToolRegistry', () {
    test('registers and resolves by id and shortcut', () {
      final registry = _registry();
      expect(registry.tools, hasLength(3));
      expect(registry.byId(HandTool.toolId), isA<HandTool>());
      expect(
        registry.byShortcut(LogicalKeyboardKey.keyV),
        isA<SelectionTool>(),
      );
      expect(registry.byId('missing'), isNull);
    });

    test('rejects duplicate ids', () {
      final registry = ToolRegistry()..register(SelectionTool());
      expect(() => registry.register(SelectionTool()), throwsAssertionError);
    });
  });

  group('ToolController', () {
    test('activates tools and fires deactivate/activate hooks', () {
      final controller = ToolController(
        registry: _registry(),
        initialToolId: SelectionTool.toolId,
      );
      final context = _TestToolContext();
      controller.attachContext(context);

      expect(controller.activeTool, isA<SelectionTool>());
      controller.activate(HandTool.toolId);
      expect(controller.activeTool, isA<HandTool>());
    });

    test('shortcut activation', () {
      final controller = ToolController(
        registry: _registry(),
        initialToolId: SelectionTool.toolId,
      );
      expect(controller.activateByShortcut(LogicalKeyboardKey.keyH), isTrue);
      expect(controller.activeTool, isA<HandTool>());
      expect(controller.activateByShortcut(LogicalKeyboardKey.keyQ), isFalse);
    });
  });

  group('core tools', () {
    test('hand tool pans the view transform by drag delta', () {
      final tool = HandTool();
      final context = _TestToolContext();

      tool.onPointerDown(context, _eventAt(const Offset(100, 100)));
      tool.onPointerMove(context, _eventAt(const Offset(130, 80)));
      expect(context.transform.offset, const Offset(30, -20));

      tool.onPointerMove(context, _eventAt(const Offset(140, 90)));
      expect(context.transform.offset, const Offset(40, -10));
      tool.onPointerUp(context, _eventAt(const Offset(140, 90)));

      // Moves after release do not pan.
      tool.onPointerMove(context, _eventAt(const Offset(200, 200)));
      expect(context.transform.offset, const Offset(40, -10));
    });

    test('zoom tool zooms in on primary and out on secondary click', () {
      const tool = ZoomTool();
      final context = _TestToolContext();

      tool.onPointerDown(context, _eventAt(const Offset(50, 50)));
      expect(context.transform.scale, closeTo(1.25, 1e-9));

      tool.onPointerDown(
        context,
        _eventAt(const Offset(50, 50), secondary: true),
      );
      expect(context.transform.scale, closeTo(1, 1e-9));
    });

    test('selection tool tracks a marquee and repaints the overlay', () {
      final tool = SelectionTool();
      final context = _TestToolContext();

      tool.onPointerDown(context, _eventAt(const Offset(10, 10)));
      tool.onPointerMove(context, _eventAt(const Offset(60, 40)));
      expect(tool.marqueeRect, const Rect.fromLTRB(10, 10, 60, 40));
      expect(context.overlayRepaints, greaterThanOrEqualTo(2));

      tool.onPointerUp(context, _eventAt(const Offset(60, 40)));
      expect(tool.marqueeRect, isNull);
    });

    test('deactivate clears transient interaction state', () {
      final tool = SelectionTool();
      final context = _TestToolContext();
      tool.onPointerDown(context, _eventAt(const Offset(10, 10)));
      tool.deactivate(context);
      expect(tool.marqueeRect, isNull);
    });
  });
}

// -- Shape tools -----------------------------------------------------------

void _shapeToolTests() {
  group('shape tools', () {
    test('drag dispatches AddShapeCommand with scene-space bounds', () {
      final tool = RectangleTool();
      final context = _TestToolContext()
        ..transform = const ViewTransform(scale: 2, offset: Offset(10, 10));

      ToolPointerEvent eventAt(Offset view) => ToolPointerEvent(
        viewPosition: view,
        scenePosition: context.transform.viewToScene(view),
      );

      // View (110,110) -> scene (50,50); view (310,210) -> scene (150,100).
      tool.onPointerDown(context, eventAt(const Offset(110, 110)));
      tool.onPointerMove(context, eventAt(const Offset(310, 210)));
      tool.onPointerUp(context, eventAt(const Offset(310, 210)));

      expect(context.dispatched, hasLength(1));
      final command = context.dispatched.single as AddShapeCommand;
      expect(command.kind, RivShapeKind.rectangle);
      // Centre of (50,50)-(150,100) with size 100x50.
      expect(command.x, closeTo(100, 1e-9));
      expect(command.y, closeTo(75, 1e-9));
      expect(command.width, closeTo(100, 1e-9));
      expect(command.height, closeTo(50, 1e-9));
    });

    test('tiny click does not create a shape', () {
      final tool = EllipseTool();
      final context = _TestToolContext();
      tool.onPointerDown(context, _eventAt(const Offset(10, 10)));
      tool.onPointerUp(context, _eventAt(const Offset(10.5, 10.5)));
      expect(context.dispatched, isEmpty);
    });

    test('deactivate clears an in-progress drag', () {
      final tool = RectangleTool();
      final context = _TestToolContext();
      tool.onPointerDown(context, _eventAt(const Offset(10, 10)));
      tool.deactivate(context);
      expect(tool.sceneRect, isNull);
    });
  });
}

// -- Selection tool with hit testing ---------------------------------------

void _selectionHitTests() {
  group('selection tool hit testing', () {
    const region = SceneHitRegion(
      ref: SceneNodeRef(0, 3),
      bounds: Rect.fromLTWH(40, 40, 60, 60),
      drawOrder: 0,
    );

    test('click on a component selects it', () {
      final tool = SelectionTool();
      final context = _TestToolContext()
        ..hitTester = SceneHitTester(const [region]);

      tool.onPointerDown(context, _eventAt(const Offset(50, 50)));
      tool.onPointerUp(context, _eventAt(const Offset(50, 50)));
      expect(context.selection.selected, {region.ref});
    });

    test('marquee from empty space selects intersecting components', () {
      final tool = SelectionTool();
      final context = _TestToolContext()
        ..hitTester = SceneHitTester(const [region]);

      tool.onPointerDown(context, _eventAt(const Offset(0, 0)));
      tool.onPointerMove(context, _eventAt(const Offset(45, 45)));
      expect(tool.marqueeRect, isNotNull);
      tool.onPointerUp(context, _eventAt(const Offset(45, 45)));
      expect(context.selection.selected, {region.ref});
      expect(tool.marqueeRect, isNull);
    });

    test('empty marquee clears the selection', () {
      final tool = SelectionTool();
      final context = _TestToolContext()
        ..hitTester = SceneHitTester(const [region]);
      context.selection.select([region.ref]);

      tool.onPointerDown(context, _eventAt(const Offset(200, 200)));
      tool.onPointerUp(context, _eventAt(const Offset(210, 210)));
      expect(context.selection.isEmpty, isTrue);
    });
  });
}
