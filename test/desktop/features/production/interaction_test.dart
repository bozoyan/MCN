// 职责: 验证场次在单击编辑、框选及组拖动中保持整体选择、等距移动和取消回退。
// 关联文件:
//   lib/desktop/features/production/interaction.dart
//   lib/desktop/features/production/board.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/interaction.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late flow.NodeFlowController<String, String> controller;
  late ProductionBoardInteraction interaction;
  late List<Map<String, Offset>> saved;
  setUp(() {
    controller = flow.NodeFlowController<String, String>();
    interaction = ProductionBoardInteraction(controller)
      ..sceneForNode = {'a1': 'a', 'a2': 'a', 'a3': 'a', 'b1': 'b', 'b2': 'b'};
    saved = [];
    for (final (i, id) in ['a1', 'a2', 'a3', 'b1', 'b2', 'free'].indexed) {
      controller.addNode(
        flow.Node<String>(
          id: id,
          type: 'video',
          data: id,
          position: Offset(i < 3 ? 0 : 400, i * 100),
          size: const Size(80, 80),
        ),
      );
    }
    controller.updateEvents(
      flow.NodeFlowEvents<String, String>(
        onSelectionChange: (_) => interaction.selectionChanged(),
        node: flow.NodeEvents<String>(
          onDragStart: (_) => interaction.startDrag(),
          onDragStop: (_) {
            final positions = interaction.finishDrag();
            if (positions.isNotEmpty) {
              saved.add(positions);
            }
          },
          onDragCancel: (_) => interaction.cancelDrag(),
        ),
      ),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'single click remains an edit focus; marquee includes the entire scene',
    () {
      controller.selectNode('a2');
      expect(controller.selectedNodeIds, {'a2'});
      controller.interaction.updateSelection(
        startPoint: const flow.GraphPosition(Offset.zero),
        rectangle: flow.GraphRect.fromPoints(
          const flow.GraphPosition(Offset.zero),
          const flow.GraphPosition(Offset(40, 150)),
        ),
      );
      controller.selectNodes(['a1']);
      expect(controller.selectedNodeIds, {'a1', 'a2', 'a3'});
      controller.interaction.finishSelection();
      expect(controller.selectedNodeIds, {'a1', 'a2', 'a3'});
    },
  );

  test(
    'mixed selection moves two whole scenes and a free node exactly once',
    () {
      controller.selectNodes(['a2', 'b1', 'free']);
      expect(controller.selectedNodeIds, {
        'a1',
        'a2',
        'a3',
        'b1',
        'b2',
        'free',
      });
      final before = {
        for (final node in controller.nodes.values)
          node.id: node.position.value,
      };
      controller.startNodeDrag('free');
      controller.moveNodeDrag(const Offset(50, -20));
      controller.endNodeDrag();
      expect(saved, hasLength(1));
      expect(saved.single.keys, unorderedEquals(before.keys));
      for (final entry in before.entries) {
        expect(saved.single[entry.key], entry.value + const Offset(50, -20));
      }
    },
  );

  test(
    'starting from a single scene node expands and cancelling restores every member',
    () {
      controller.selectNode('a2');
      final before = {
        for (final node in controller.nodes.values)
          node.id: node.position.value,
      };
      controller.startNodeDrag('a2');
      expect(controller.selectedNodeIds, {'a1', 'a2', 'a3'});
      controller.moveNodeDrag(const Offset(40, 10));
      expect(
        controller.getNode('a1')!.position.value,
        before['a1']! + const Offset(40, 10),
      );
      controller.cancelNodeDrag(
        Map.of(controller.interaction.dragStartPositions),
      );
      expect(saved, isEmpty);
      for (final entry in before.entries) {
        expect(controller.getNode(entry.key)!.position.value, entry.value);
      }
    },
  );

  test('selecting one scene leaves the other scene stationary', () {
    controller.selectNodes(['a2', 'free']);
    final other = controller.getNode('b1')!.position.value;
    controller.startNodeDrag('a1');
    controller.moveNodeDrag(const Offset(50, 10));
    controller.endNodeDrag();
    expect(saved.single.keys, unorderedEquals(['a1', 'a2', 'a3', 'free']));
    expect(controller.getNode('b1')!.position.value, other);
  });
}
