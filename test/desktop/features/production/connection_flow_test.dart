// 职责: 验证制作画布关联连线的选择高亮、流光限帧、重绘隔离及停止恢复。
// 关联文件:
//   lib/desktop/features/production/connection_flow.dart
//   lib/desktop/features/production/board.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/layers/interaction_layer.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/connection_flow.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/layers/interaction_layer.dart';

void main() {
  final colors = RevericThemeData.reveric.colors;
  late ProductionConnectionFlow highlight;
  late flow.NodeFlowController<String, String> controller;

  void configure({bool animate = true}) => highlight.configure(
    colors: colors,
    connectionLabels: {
      for (final connection in controller.connections)
        connection.id: 'Reference',
    },
    animate: animate,
  );
  flow.Connection<String> edge(String id, String from, String to) =>
      flow.Connection<String>(
        id: id,
        sourceNodeId: from,
        sourcePortId: 'out',
        targetNodeId: to,
        targetPortId: 'in',
        data: 'reference_image',
        dashPattern: const [4, 5],
      );
  setUp(() {
    highlight = ProductionConnectionFlow(colors);
    controller = flow.NodeFlowController<String, String>(
      config: flow.NodeFlowConfig(showAttribution: false, plugins: [highlight]),
    );
    for (final (i, id) in ['c', 'a', 'b', 'd', 'e'].indexed) {
      controller.addNode(
        flow.Node<String>(
          id: id,
          type: 'image',
          data: id,
          position: Offset(40 + (i % 3) * 220, 80 + (i ~/ 3) * 220),
          size: const Size(100, 80),
          ports: [
            flow.Port(
              id: 'in',
              name: '',
              type: flow.PortType.input,
              position: flow.PortPosition.left,
              offset: const Offset(0, 40),
            ),
            flow.Port(
              id: 'out',
              name: '',
              type: flow.PortType.output,
              position: flow.PortPosition.right,
              offset: const Offset(0, 40),
            ),
          ],
        ),
      );
    }
    controller.addConnection(edge('incoming', 'c', 'a'));
    controller.addConnection(edge('outgoing', 'a', 'b'));
    controller.addConnection(edge('unrelated', 'd', 'e'));
    controller.resolvePlugin<ProductionConnectionFlow>();
    configure();
  });
  tearDown(() => controller.dispose());

  test('single selection animates incoming and outgoing edges only', () {
    controller.selectNode('a');
    expect(
      controller.getConnection('incoming')!.animationEffect,
      isA<flow.GradientFlowEffect>(),
    );
    expect(
      controller.getConnection('outgoing')!.animationEffect,
      isA<flow.GradientFlowEffect>(),
    );
    expect(controller.getConnection('unrelated')!.animationEffect, isNull);
    expect(controller.getConnection('incoming')!.label?.text, 'Reference');
    expect(controller.getConnection('outgoing')!.label, isNull);
    expect(controller.getConnection('incoming')!.dashPattern, [4, 5]);
  });

  test(
    'multi selection animates all incident edges and clears immediately',
    () {
      controller.selectNodes(['a', 'd']);
      final effect = controller.getConnection('incoming')!.animationEffect;
      expect(effect, isNotNull);
      for (final connection in controller.connections) {
        expect(connection.animationEffect, same(effect));
        expect(connection.label, isNull);
      }
      controller.clearSelection();
      for (final connection in controller.connections) {
        expect(connection.animationEffect, isNull);
        expect(connection.animated, isFalse);
        expect(connection.dashPattern, [4, 5]);
      }
    },
  );

  test('new edges and selection switches update without parent rebuilds', () {
    controller.selectNode('b');
    controller.addConnection(edge('new', 'c', 'b'));
    expect(controller.getConnection('new')!.animationEffect, isNotNull);
    controller.selectNode('e');
    expect(controller.getConnection('new')!.animationEffect, isNull);
    expect(controller.getConnection('outgoing')!.animationEffect, isNull);
    expect(controller.getConnection('unrelated')!.animationEffect, isNotNull);
  });

  test('labels update in place after role and mode changes', () {
    controller.selectNode('a');
    final incoming = controller.getConnection('incoming')!;
    for (final label in [
      'Last frame',
      'First frame',
      'First-frame reference',
    ]) {
      highlight.configure(
        colors: colors,
        connectionLabels: {'incoming': label},
        animate: false,
      );
      expect(controller.getConnection('incoming'), same(incoming));
      expect(incoming.label?.text, label);
      expect(controller.selectedNodeIds, {'a'});
    }
  });

  test('reduced motion keeps static highlighting and can be changed live', () {
    controller.selectNode('a');
    configure(animate: false);
    expect(
      controller.connections.every((edge) => edge.animationEffect == null),
      isTrue,
    );
    expect(
      controller.getConnection('incoming')!.color,
      colors.accent.withValues(alpha: .95),
    );
    configure();
    expect(controller.getConnection('incoming')!.animationEffect, isNotNull);
  });

  test('detaching removes effects and selection subscriptions', () {
    controller.selectNode('a');
    controller.removePlugin(highlight.id);
    controller.selectNode('e');
    expect(
      controller.connections.every((edge) => edge.animationEffect == null),
      isTrue,
    );
  });

  testWidgets(
    '30 fps flow limits actual frames while viewport movement stays responsive',
    (tester) async {
      var enabled = true;
      late StateSetter setMode;
      var frames = 0;
      var recording = true;
      tester.binding.addPersistentFrameCallback((_) {
        if (recording) {
          frames++;
        }
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                setMode = setState;
                return TickerMode(
                  enabled: enabled,
                  child: flow.NodeFlowEditor<String, String>(
                    controller: controller,
                    theme: flow.NodeFlowTheme.light,
                    connectionAnimationFrameRate: 30,
                    nodeBuilder: (_, _) => ColoredBox(color: colors.surface),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.selectNode('a');
        await tester.pump();
        frames = 0;
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(microseconds: 8334));
        }
        expect(frames, inInclusiveRange(29, 31));
        expect(tester.binding.transientCallbackCount, 0);

        frames = 0;
        for (var i = 0; i < 60; i++) {
          controller.setViewport(flow.GraphViewport(x: i + 1.0));
          await tester.pump(const Duration(microseconds: 8334));
        }
        expect(frames, 60);

        setMode(() => enabled = false);
        await tester.pump();
        frames = 0;
        await tester.pump(const Duration(seconds: 1));
        expect(frames, 0);
        setMode(() => enabled = true);
        await tester.pump();
        frames = 0;
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(microseconds: 8334));
        }
        expect(frames, inInclusiveRange(29, 31));

        controller.clearSelection();
        await tester.pumpAndSettle();
        frames = 0;
        await tester.pump(const Duration(seconds: 1));
        expect(frames, 0);
      } finally {
        recording = false;
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'animation repaints incident edges without repainting unrelated edges',
    (tester) async {
      final paints = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: flow.NodeFlowEditor<String, String>(
            controller: controller,
            theme: flow.NodeFlowTheme.light,
            nodeBuilder: (_, _) => ColoredBox(color: colors.surface),
            connectionStyleBuilder: (connection, _, _) {
              paints.update(connection.id, (n) => n + 1, ifAbsent: () => 1);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.selectNode('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(paints.keys, containsAll(['incoming', 'outgoing', 'unrelated']));
      final interaction = tester.renderObject<RenderCustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is InteractionLayerPainter<String>,
        ),
      );
      RenderObject? ancestor = interaction.parent;
      while (ancestor is! RenderRepaintBoundary) {
        ancestor = ancestor!.parent;
      }
      final interactionBoundary = ancestor;
      interactionBoundary.debugResetMetrics();
      paints.clear();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paints['incoming'], 5);
      expect(paints['outgoing'], 5);
      expect(paints['unrelated'] ?? 0, 0);
      expect(
        interactionBoundary.debugAsymmetricPaintCount +
            interactionBoundary.debugSymmetricPaintCount,
        0,
      );

      controller.startNodeDrag('a');
      await tester.pump();
      paints.clear();
      await tester.pump(const Duration(milliseconds: 16));
      expect(paints, {'incoming': 1, 'outgoing': 1});
      controller.endNodeDrag();
      await tester.pump();
      paints.clear();
      await tester.pump(const Duration(milliseconds: 16));
      expect(paints, {'incoming': 1, 'outgoing': 1});

      controller.selectNode('e');
      await tester.pump();
      paints.clear();
      await tester.pump(const Duration(milliseconds: 16));
      expect(paints, {'unrelated': 1});

      configure(animate: false);
      await tester.pumpAndSettle();
      paints.clear();
      await tester.pump(const Duration(milliseconds: 100));
      expect(paints, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'theme animation still paints every edge without node selection',
    (tester) async {
      final paints = <String, int>{};
      final theme = flow.NodeFlowTheme.light.copyWith(
        connectionTheme: flow.NodeFlowTheme.light.connectionTheme.copyWith(
          animationEffect: flow.GradientFlowEffect(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: flow.NodeFlowEditor<String, String>(
            controller: controller,
            theme: theme,
            nodeBuilder: (_, _) => ColoredBox(color: colors.surface),
            connectionStyleBuilder: (connection, _, _) {
              paints.update(connection.id, (n) => n + 1, ifAbsent: () => 1);
              return null;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      paints.clear();
      await tester.pump(const Duration(milliseconds: 16));
      expect(paints, {'incoming': 1, 'outgoing': 1, 'unrelated': 1});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'flow paints changing frames and stops scheduling after deselection',
    (tester) async {
      const capture = ValueKey('flow-capture');
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: capture,
            child: flow.NodeFlowEditor<String, String>(
              controller: controller,
              theme: flow.NodeFlowTheme.light,
              nodeBuilder: (_, _) => ColoredBox(color: colors.surface),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      controller.selectNode('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      Future<List<int>> pixels(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          const captureDir = String.fromEnvironment('FLOW_CAPTURE_DIR');
          if (captureDir.isNotEmpty) {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$captureDir/$name.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          }
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List().toList();
        }))!;
      }

      final first = await pixels('production-flow-1');
      await tester.pump(const Duration(milliseconds: 450));
      final next = await pixels('production-flow-2');
      expect(next, isNot(orderedEquals(first)));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
