// 职责: 验证节点容器缓存复用以及控制器切换后的拖动权限和事件归属。
// 关联文件:
//   lib/third/flow/vyuh_node_flow/lib/src/editor/layers/nodes_layer.dart
//   lib/third/flow/vyuh_node_flow/lib/src/nodes/node_container.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/element_scope.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/element_scope.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/layers/nodes_layer.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/nodes/node_container.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.android,
  ]) {
    testWidgets('cached nodes follow the new controller on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final node = Node<String>(
        id: 'node',
        type: 'test',
        position: const Offset(100, 100),
        data: 'node',
      );
      final first = NodeFlowController<String, String>(nodes: [node]);
      final second = NodeFlowController<String, String>(nodes: [node]);
      for (final controller in [first, second]) {
        controller.initController(
          theme: NodeFlowTheme.light,
          portSizeResolver: (_) => const Size(8, 8),
        );
        controller.setScreenSize(const Size(800, 600));
      }
      first.setBehavior(NodeFlowBehavior.design);
      second.setBehavior(NodeFlowBehavior.inspect);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        first.dispose();
        second.dispose();
        debugDefaultTargetPlatformOverride = null;
      });

      try {
        Widget build(NodeFlowController<String, String> controller) =>
            MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    NodesLayer<String>(
                      controller: controller,
                      nodeBuilder: (_, _) => const SizedBox(),
                    ),
                  ],
                ),
              ),
            );

        final containers = find.byType(NodeContainer<String>);
        final scope = find.byType(ElementScope);
        final kind = platform == TargetPlatform.android
            ? PointerDeviceKind.touch
            : PointerDeviceKind.mouse;
        await tester.pumpWidget(build(first));
        final cached = tester.widget<NodeContainer<String>>(containers);
        await tester.pumpWidget(build(first));
        expect(tester.widget<NodeContainer<String>>(containers), same(cached));

        // Reuse the node and content to isolate controller cache invalidation.
        await tester.pumpWidget(build(second));
        final position = node.position.value;
        await tester.drag(scope, const Offset(80, 40), kind: kind);
        await tester.pump();
        expect(node.position.value, position);
        expect(
          tester.widget<NodeContainer<String>>(containers).controller,
          same(second),
        );

        // The cached subtree must observe the new controller's behavior changes.
        second.setBehavior(NodeFlowBehavior.design);
        await tester.pump();
        final pointer = await tester.startGesture(
          tester.getCenter(scope),
          kind: kind,
        );
        await pointer.moveBy(const Offset(80, 40));
        await tester.pump();
        expect(node.position.value, position + const Offset(80, 40));
        expect(second.draggedNodeId, node.id);
        expect(first.draggedNodeId, isNull);
        await pointer.up();
        await pointer.removePointer();
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
