// 职责: 画布 AI 分镜导演测试 — 守住「调用逐个演、工具等演完、镜头先于揭示、一轮只定一次缩放、接管即补齐」
// 关联文件:
//   lib/desktop/features/canvas/canvas_ai_director.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/shared/models/canvas_ai_activity.dart

import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_ai_director.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/canvas_ai_activity.dart';
import 'package:reveric/shared/theme/theme.dart';
// getNode / getConnection 是 controller 的 extension 方法，须显式引入定义库。
import 'package:reveric/third/flow/vyuh_node_flow.dart';

const _canvasId = 'canvas_ai_test';

/// 典型画布区尺寸(桌面窗口减去 chat panel)。
const Size _screen = Size(1100, 760);

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

/// 造一个便签节点。故意摆在视野外(x 从 2000 起)，这样镜头一定要动 ——
/// 「镜头先于揭示」的断言需要真的有一次镜头动作。
CanvasNode _node(String id, {required int index}) {
  return CanvasNode(
    id: id,
    canvasId: _canvasId,
    type: canvasNodeTypeSticky,
    title: id,
    content: '正文 $id',
    x: 2000 + index * 320,
    y: 600,
    zIndex: 0,
    sortOrder: index,
    createdAt: _epoch,
    updatedAt: _epoch,
    deletedAt: notDeletedSentinel,
  );
}

CanvasEdge _edge(String id, String source, String target) {
  return CanvasEdge(
    id: id,
    canvasId: _canvasId,
    sourceNodeId: source,
    targetNodeId: target,
    type: canvasEdgeTypeAssociation,
    createdAt: _epoch,
    updatedAt: _epoch,
  );
}

CanvasAiActivity _activity(
  CanvasAiActivityKind kind, {
  List<String> focus = const <String>[],
}) {
  return CanvasAiActivity(canvasId: _canvasId, kind: kind, focusNodeIds: focus);
}

void main() {
  late CanvasFlowController controller;
  late CanvasAiDirector director;
  late List<GraphViewport> moves;

  /// 模拟 board 的增量挂载：先把内容加进 controller，再交给导演挑走 AI 写的部分。
  CanvasAiStagedContent mount(
    List<CanvasNode> nodes, {
    List<CanvasEdge> edges = const <CanvasEdge>[],
  }) {
    final colors = RevericThemeData.reveric.colors;
    final nodeById = {for (final node in nodes) node.id: node};
    for (final node in nodes) {
      controller.addNode(canvasNodeToFlowNode(node, colors: colors));
    }
    for (final edge in edges) {
      controller.addConnection(
        canvasEdgeToFlowConnection(
          edge,
          colors: colors,
          sourceCenter: canvasNodeCenter(nodeById[edge.sourceNodeId]!),
          targetCenter: canvasNodeCenter(nodeById[edge.targetNodeId]!),
        ),
      );
    }
    return director.stageIncremental(
      addedNodeIds: [for (final node in nodes) node.id],
      addedEdgeIds: [for (final edge in edges) edge.id],
    );
  }

  bool visible(String nodeId) => controller.getNode(nodeId)?.isVisible ?? false;

  int visibleCount(List<CanvasNode> nodes) =>
      nodes.where((node) => visible(node.id)).length;

  setUp(() {
    moves = <GraphViewport>[];
    controller = CanvasFlowController();
    controller.loadGraph(
      canvasContentToFlowGraph(
        const <CanvasNode>[],
        const <CanvasEdge>[],
        colors: RevericThemeData.reveric.colors,
      ),
    );
    controller.setScreenSize(_screen);
    controller.setAnimateToHandler((
      target, {
      Duration duration = const Duration(milliseconds: 400),
      Curve curve = Curves.easeInOut,
    }) {
      moves.add(target);
    }, token: 'test');
    director = CanvasAiDirector(canvasId: _canvasId);
    director.attach(controller);
  });

  tearDown(() {
    director.dispose();
    controller.dispose();
  });

  test('批量调用被拖成一个接一个：工具等这一步演完才继续', () async {
    final nodes = [for (var i = 0; i < 4; i++) _node('n$i', index: i)];
    final watch = Stopwatch()..start();
    // 模拟批量处理：写库 → 上报 → DB stream 回流挂载 → 等导演放行，再写下一个。
    for (var i = 0; i < nodes.length; i++) {
      final pacing = director.onActivity(
        _activity(CanvasAiActivityKind.add_node, focus: [nodes[i].id]),
      );
      mount([nodes[i]]);
      expect(visible(nodes[i].id), isFalse, reason: '镜头就位之前不该露面');

      await pacing;
      // 放行时这一步已经演完，后面的还没写进来。
      expect(visibleCount(nodes.sublist(0, i + 1)), i + 1);
    }
    // 每一步至少停一个节奏间隔，四步不可能一瞬间跑完。
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 600)),
    );
  });

  test('同一帧并发的调用全部接管，并按到达顺序逐个揭示', () async {
    final nodes = [for (var i = 0; i < 3; i++) _node('n$i', index: i)];
    final done = <String>[];
    // 每一步放行时记下画面上已经露面的节点。
    final visibleAtRelease = <String, int>{};
    final pacings = [
      for (final node in nodes)
        director
            .onActivity(
              _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
            )
            .then((_) {
              done.add(node.id);
              visibleAtRelease[node.id] = visibleCount(nodes);
            }),
    ];

    final staged = mount(nodes);
    expect(staged.nodeIds, [for (final node in nodes) node.id]);
    expect(visibleCount(nodes), 0);

    await Future.wait(pacings);
    expect(done, ['n0', 'n1', 'n2']);
    // 一个一个露面，而不是同一拍成片冒出来。
    expect(visibleAtRelease, {'n0': 1, 'n1': 2, 'n2': 3});
  });

  test('镜头先就位，内容后落下', () async {
    final node = _node('n0', index: 0);
    unawaited(
      director.onActivity(
        _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
      ),
    );
    mount([node]);

    // 镜头(520ms)还在飞：画面上不能冒出节点。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(moves.length, 1);
    expect(visible(node.id), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(visible(node.id), isTrue);
  });

  test('一轮里缩放只定一次，之后只平移', () async {
    // 一字排开、越走越远：每个都在视野外，镜头每一步都要动。
    final nodes = [
      for (var i = 0; i < 3; i++)
        _node('n$i', index: i).copyWith(x: 2000.0 + i * 1600),
    ];
    for (final node in nodes) {
      final pacing = director.onActivity(
        _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
      );
      mount([node]);
      await pacing;
    }

    expect(moves.length, nodes.length);
    expect(moves.map((viewport) => viewport.zoom).toSet(), hasLength(1));
    // 首拍只有一个节点，全貌缩放会顶到 1.2；锁定值要压回能看出结构的范围。
    expect(moves.first.zoom, lessThanOrEqualTo(0.62));
  });

  test('连线在节点之后生长', () async {
    final nodes = [for (var i = 0; i < 2; i++) _node('n$i', index: i)];
    for (final node in nodes) {
      final pacing = director.onActivity(
        _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
      );
      mount([node]);
      await pacing;
    }

    final pacing = director.onActivity(
      _activity(CanvasAiActivityKind.add_edge, focus: ['n0', 'n1']),
    );
    controller.addConnection(
      canvasEdgeToFlowConnection(
        _edge('e0', 'n0', 'n1'),
        colors: RevericThemeData.reveric.colors,
        sourceCenter: canvasNodeCenter(nodes[0]),
        targetCenter: canvasNodeCenter(nodes[1]),
      ),
    );
    final staged = director.stageIncremental(
      addedNodeIds: const <String>[],
      addedEdgeIds: const ['e0'],
    );

    expect(staged.edgeIds, ['e0']);
    expect(controller.getConnection('e0')?.visible, isFalse);

    await pacing;
    expect(controller.getConnection('e0')?.visible, isTrue);
  });

  test('连线一端已在画面里：不动镜头、不给两端点环', () async {
    final near = _node('near', index: 0);
    final far = _node('far', index: 0).copyWith(x: -4000, y: 3000);
    for (final node in [near, far]) {
      final pacing = director.onActivity(
        _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
      );
      mount([node]);
      await pacing;
    }
    // 把镜头摆回 near 上，模拟时间线正在画面里。
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    controller.setViewport(
      GraphViewport(
        x: _screen.width / 2 - (near.x + 140) * 0.62,
        y: _screen.height / 2 - (near.y + 84) * 0.62,
        zoom: 0.62,
      ),
    );
    final movesBefore = moves.length;
    final stampsBefore = Map.of(director.focusStamps);

    final pacing = director.onActivity(
      _activity(CanvasAiActivityKind.add_edge, focus: ['far', 'near']),
    );
    controller.addConnection(
      canvasEdgeToFlowConnection(
        _edge('e0', 'far', 'near'),
        colors: RevericThemeData.reveric.colors,
        sourceCenter: canvasNodeCenter(far),
        targetCenter: canvasNodeCenter(near),
      ),
    );
    director.stageIncremental(
      addedNodeIds: const <String>[],
      addedEdgeIds: const ['e0'],
    );
    await pacing;

    expect(moves.length, movesBefore);
    expect(director.focusStamps, stampsBefore);
    expect(controller.getConnection('e0')?.visible, isTrue);
  });

  test('节点没走增量挂载就自己露面了，镜头照样跟过去', () async {
    final node = _node('n0', index: 0);
    final pacing = director.onActivity(
      _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
    );
    // 整图重载路径：内容直接可见，stageIncremental 不会被调用。
    controller.addNode(
      canvasNodeToFlowNode(node, colors: RevericThemeData.reveric.colors),
    );

    // 等回流到上限(600ms)后照样出镜头、点环。
    await pacing;
    expect(moves.length, 1);
    expect(director.focusStamps.containsKey(node.id), isTrue);
  });

  test('用户自己加的内容不被接管 —— 点一下工具栏必须立刻出现', () {
    final node = _node('user_sticky', index: 0);
    // 没有对应的 add_node 事件：这是用户自己加的。
    final staged = mount([node]);

    expect(staged.isEmpty, isTrue);
    expect(visible(node.id), isTrue);
  });

  test('用户接管：内容立刻补齐、镜头交还，节奏照旧', () async {
    final nodes = [for (var i = 0; i < 3; i++) _node('n$i', index: i)];
    for (final node in nodes) {
      unawaited(
        director.onActivity(
          _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
        ),
      );
    }
    mount(nodes);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    director.handOver();

    // 这条是硬要求：用户点一下画布，不能只拿到半张图。
    expect(visibleCount(nodes), nodes.length);
    expect(director.isFollowing, isFalse);
    final movesAtHandOver = moves.length;

    // 接管之后的新内容立刻可见，但工具仍按节奏放行 —— 剩余节点不会成片冒出来。
    final later = _node('n_late', index: 9);
    var released = false;
    unawaited(
      director
          .onActivity(
            _activity(CanvasAiActivityKind.add_node, focus: [later.id]),
          )
          .then((_) => released = true),
    );
    expect(mount([later]).isEmpty, isTrue);
    expect(visible(later.id), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(released, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(released, isTrue);
    expect(moves.length, movesAtHandOver, reason: '镜头已经交还，不再动');
  });

  test('detach 放出藏起来的内容，并放行所有等待中的工具', () async {
    final nodes = [for (var i = 0; i < 3; i++) _node('n$i', index: i)];
    final pacings = [
      for (final node in nodes)
        director.onActivity(
          _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
        ),
    ];
    mount(nodes);
    expect(visibleCount(nodes), 0);

    director.detach();

    expect(visibleCount(nodes), nodes.length);
    await Future.wait(pacings).timeout(const Duration(milliseconds: 100));
  });

  test('整图重载后不再空转：内容已可见，镜头与高亮环照给', () async {
    final nodes = [for (var i = 0; i < 3; i++) _node('n$i', index: i)];
    final pacings = [
      for (final node in nodes)
        director.onActivity(
          _activity(CanvasAiActivityKind.add_node, focus: [node.id]),
        ),
    ];
    mount(nodes);

    // loadGraph 重建全部节点，隐藏态随之消失。
    controller.loadGraph(
      canvasContentToFlowGraph(
        nodes,
        const <CanvasEdge>[],
        colors: RevericThemeData.reveric.colors,
      ),
    );
    director.onGraphReloaded();

    await Future.wait(pacings);
    expect(visibleCount(nodes), nodes.length);
    expect(director.focusStamps.keys, containsAll(['n0', 'n1', 'n2']));
  });

  test('状态条：单一操作说具体动作，混合操作说一句聚合文案', () {
    director.onActivity(
      _activity(CanvasAiActivityKind.add_node, focus: ['n0']),
    );
    expect(director.statusVisible, isTrue);
    expect(director.statusKind, CanvasAiActivityKind.add_node);
    expect(director.isMultiKind, isFalse);

    director.onActivity(
      _activity(CanvasAiActivityKind.add_edge, focus: ['n0', 'n1']),
    );
    expect(director.isMultiKind, isTrue);
    expect(director.statusKind, isNull);
  });

  test('只读 scan 立刻放行，不排任何镜头', () async {
    await director
        .onActivity(_activity(CanvasAiActivityKind.scan))
        .timeout(const Duration(milliseconds: 50));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(moves, isEmpty);
    expect(director.statusKind, CanvasAiActivityKind.scan);
  });

  test('一轮放慢的总时长有上限，超过后不再等', () {
    fakeAsync((async) {
      // 换一组在假时钟里创建的导演，Timer 才归 fakeAsync 推进。
      final fakeDirector = CanvasAiDirector(canvasId: _canvasId)
        ..attach(controller);
      var released = 0;
      // 每一步至少 150ms：100 步不封顶要 15 秒以上。
      for (var i = 0; i < 100; i++) {
        fakeDirector
            .onActivity(
              _activity(CanvasAiActivityKind.update_node, focus: const []),
            )
            .then((_) => released += 1);
      }

      async.elapse(const Duration(seconds: 11));
      expect(released, 100);
      fakeDirector.dispose();
    });
  });
}
