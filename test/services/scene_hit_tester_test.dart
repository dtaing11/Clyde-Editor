import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/model/scene_node_ref.dart';
import 'package:rive_editor/src/core/services/scene_hit_tester.dart';
import 'package:rive_editor/src/riv/riv_document_builder.dart';
import 'package:rive_editor/src/riv/riv_hit_regions.dart';
import 'package:rive_editor/src/riv/riv_raw_document.dart';
import 'package:rive_editor/src/riv/riv_shape_factory.dart';

void main() {
  group('SceneHitTester', () {
    const bottom = SceneHitRegion(
      ref: SceneNodeRef(0, 1),
      bounds: Rect.fromLTWH(0, 0, 100, 100),
      drawOrder: 0,
    );
    const top = SceneHitRegion(
      ref: SceneNodeRef(0, 5),
      bounds: Rect.fromLTWH(50, 50, 100, 100),
      drawOrder: 1,
    );

    test('point query returns the topmost overlapping region', () {
      final tester = SceneHitTester(const [bottom, top]);
      expect(tester.hitTest(const Offset(75, 75))!.ref, top.ref);
      expect(tester.hitTest(const Offset(10, 10))!.ref, bottom.ref);
      expect(tester.hitTest(const Offset(500, 500)), isNull);
    });

    test('rect query returns every intersecting region', () {
      final tester = SceneHitTester(const [bottom, top]);
      final hits = tester.hitTestRect(const Rect.fromLTWH(40, 40, 30, 30));
      expect(hits.map((h) => h.ref), containsAll([bottom.ref, top.ref]));
      expect(
        tester.hitTestRect(const Rect.fromLTWH(300, 300, 10, 10)),
        isEmpty,
      );
    });

    test('boundsOf resolves by ref', () {
      final tester = SceneHitTester(const [bottom, top]);
      expect(tester.boundsOf(top.ref), top.bounds);
      expect(tester.boundsOf(const SceneNodeRef(0, 99)), isNull);
    });
  });

  group('RivHitRegions', () {
    test('factory-created shape produces a centred region', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      RivShapeFactory.addShape(
        raw,
        artboardOrdinal: 0,
        kind: RivShapeKind.rectangle,
        name: 'R',
        x: 200,
        y: 150,
        width: 80,
        height: 40,
        color: 0xFFFFFFFF,
      );

      final regions = RivHitRegions.forArtboard(raw, 0);
      expect(regions, hasLength(1));
      final bounds = regions.single.bounds;
      expect(bounds.center.dx, closeTo(200, 1e-6));
      expect(bounds.center.dy, closeTo(150, 1e-6));
      expect(bounds.width, closeTo(80, 1e-6));
      expect(bounds.height, closeTo(40, 1e-6));
    });

    test('later shapes get higher draw order', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      for (var i = 0; i < 2; i++) {
        RivShapeFactory.addShape(
          raw,
          artboardOrdinal: 0,
          kind: RivShapeKind.ellipse,
          name: 'S$i',
          x: 100,
          y: 100,
          width: 50,
          height: 50,
          color: 0xFF000000,
        );
      }
      final regions = RivHitRegions.forArtboard(raw, 0);
      expect(regions, hasLength(2));
      expect(regions[1].drawOrder, greaterThan(regions[0].drawOrder));

      // Overlapping shapes: hit test picks the later (topmost) one.
      final tester = SceneHitTester(regions);
      expect(tester.hitTest(const Offset(100, 100))!.ref, regions[1].ref);
    });

    test('missing artboard yields no regions', () {
      final raw = RivRawDocument.parse(RivDocumentBuilder.newDocument());
      expect(RivHitRegions.forArtboard(raw, 7), isEmpty);
    });
  });
}
