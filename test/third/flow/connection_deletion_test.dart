// 职责: 验证键盘删除保留连线泛型，并遵循异步确认、锁定和只读限制。
// 关联文件:
//   lib/third/flow/vyuh_node_flow/lib/src/editor/controller/node_flow_controller.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/controller/graph_api.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/keyboard/keyboard_actions.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart';

void main() {
  for (final key in [LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace]) {
    testWidgets(
      '${key.keyLabel} awaits typed confirmation and honors rejection',
      (tester) async {
        final controller = NodeFlowController<String, String>(
          config: NodeFlowConfig(plugins: []),
        );
        addTearDown(controller.dispose);
        final edge = Connection<String>(
          id: 'edge',
          sourceNodeId: 'source',
          sourcePortId: 'out',
          targetNodeId: 'target',
          targetPortId: 'in',
          data: 'reference_image',
        );
        var confirmation = Completer<bool>();
        final requested = <Connection<String>>[];
        final deleted = <Connection<String>>[];
        controller.updateEvents(
          NodeFlowEvents<String, String>(
            connection: ConnectionEvents<String, String>(
              onBeforeDelete: (connection) {
                requested.add(connection);
                return confirmation.future;
              },
              onDeleted: deleted.add,
            ),
          ),
        );
        controller.addConnection(edge);
        controller.selectConnection(edge.id);
        await tester.pumpWidget(
          MaterialApp(
            home: NodeFlowKeyboardHandler<String>(
              controller: controller,
              focusNode: controller.canvasFocusNode,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.canvasFocusNode.hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(requested, [edge]);
        expect(controller.getConnection(edge.id), same(edge));
        confirmation.complete(false);
        await tester.pump();
        expect(controller.getConnection(edge.id), same(edge));
        expect(deleted, isEmpty);

        confirmation = Completer<bool>();
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(requested, [edge, edge]);
        expect(controller.getConnection(edge.id), same(edge));
        confirmation.complete(true);
        await tester.pump();
        expect(controller.getConnection(edge.id), isNull);
        expect(deleted.single.data, 'reference_image');
        expect(controller.selectedConnectionIds, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.android,
      }),
    );
  }

  test(
    'erased controller preserves callback-owned removal and guards',
    () async {
      final controller = NodeFlowController<String, Map<String, String>>(
        config: NodeFlowConfig(plugins: []),
      );
      addTearDown(controller.dispose);
      final NodeFlowController<String, dynamic> erased = controller;
      var calls = 0;
      final deleted = <Connection<Map<String, String>>>[];
      controller.updateEvents(
        NodeFlowEvents<String, Map<String, String>>(
          connection: ConnectionEvents<String, Map<String, String>>(
            onBeforeDelete: (edge) async {
              calls++;
              expect(edge.data, {'role': 'reference_image'});
              await Future<void>.value();
              // 制作画布由持久化快照移除连线，回调返回 false 阻止重复删除。
              controller.removeConnection(edge.id);
              return false;
            },
            onDeleted: deleted.add,
          ),
        ),
      );
      for (final locked in [false, true]) {
        controller.addConnection(
          Connection<Map<String, String>>(
            id: locked ? 'locked' : 'editable',
            sourceNodeId: 'source',
            sourcePortId: 'out',
            targetNodeId: 'target',
            targetPortId: 'in',
            data: {'role': 'reference_image'},
            locked: locked,
          ),
        );
      }
      controller.selectConnection('editable');
      controller.selectConnection('locked', toggle: true);
      controller.setBehavior(NodeFlowBehavior.preview);
      await erased.deleteSelectedWithConfirmation();
      expect(calls, 0);
      expect(controller.connectionCount, 2);
      controller.setBehavior(NodeFlowBehavior.design);
      await erased.deleteSelectedWithConfirmation();
      expect(calls, 1);
      expect(deleted.single.id, 'editable');
      expect(controller.connectionIds, ['locked']);
    },
  );
}
