import 'package:flutter_test/flutter_test.dart';
import 'package:rive_editor/src/core/model/scene_node_ref.dart';
import 'package:rive_editor/src/core/services/selection_service.dart';

const _a1 = SceneNodeRef(0, 1);
const _a2 = SceneNodeRef(0, 2);
const _a3 = SceneNodeRef(0, 3);
const _b1 = SceneNodeRef(1, 1);

void main() {
  group('SelectionService', () {
    test('replace selects exactly the given nodes and sets primary', () {
      final service = SelectionService();
      service.select([_a1, _a2]);
      expect(service.selected, {_a1, _a2});
      expect(service.primary, _a2);
      expect(service.anchor, _a2);

      service.select([_a3]);
      expect(service.selected, {_a3});
      expect(service.primary, _a3);
    });

    test('toggle adds and removes without touching others', () {
      final service = SelectionService()..select([_a1]);
      service.select([_a2], mode: SelectionMode.toggle);
      expect(service.selected, {_a1, _a2});

      service.select([_a1], mode: SelectionMode.toggle);
      expect(service.selected, {_a2});
    });

    test('range extends the selection additively', () {
      final service = SelectionService()..select([_a1]);
      service.select([_a2, _a3], mode: SelectionMode.range);
      expect(service.selected, {_a1, _a2, _a3});
      expect(service.primary, _a3);
      // Anchor stays at the replace target for subsequent ranges.
      expect(service.anchor, _a1);
    });

    test('clear empties selection and notifies once', () {
      final service = SelectionService()..select([_a1, _b1]);
      var notifications = 0;
      service.addListener(() => notifications++);
      service.clear();
      expect(service.isEmpty, isTrue);
      expect(service.primary, isNull);
      expect(notifications, 1);

      // Clearing an empty selection does not notify.
      service.clear();
      expect(notifications, 1);
    });

    test('remap migrates indices and drops removed nodes', () {
      final service = SelectionService()..select([_a1, _a2, _b1]);
      service.applyComponentRemap(0, {1: 5, 2: -1});

      expect(service.selected, {const SceneNodeRef(0, 5), _b1});
      // Other artboards are untouched.
      expect(service.contains(_b1), isTrue);
    });

    test('remap migrates primary and anchor', () {
      final service = SelectionService()..select([_a1]);
      service.applyComponentRemap(0, {1: 7});
      expect(service.primary, const SceneNodeRef(0, 7));
      expect(service.anchor, const SceneNodeRef(0, 7));

      service.applyComponentRemap(0, {7: -1});
      expect(service.primary, isNull);
      expect(service.isEmpty, isTrue);
    });

    test('selected view is unmodifiable', () {
      final service = SelectionService()..select([_a1]);
      expect(() => service.selected.add(_a2), throwsUnsupportedError);
    });
  });
}
