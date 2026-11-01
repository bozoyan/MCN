// 职责: 画布 AI 实时分镜导演 — 按工具调用逐步揭示内容、跟随镜头，并以播放进度给工具背压
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/canvas_camera_policy.dart
//   lib/desktop/features/canvas/widgets/canvas_edge_grow_effect.dart
//   lib/shared/models/canvas_ai_activity.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/performance.md

import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Curves;

import '../../../shared/models/canvas_ai_activity.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import 'canvas_camera_policy.dart';
import 'widgets/canvas_edge_grow_effect.dart';
import 'widgets/canvas_flow_adapter.dart';

/// 一次增量挂载里被导演接管的内容。
///
/// board 据此知道哪些节点/边已经被藏起来交给导演编排 —— 剩下的（用户自己加的
/// 节点、用户拖出来的连线）仍走原来的「立刻可见 + 立刻生长」路径。
@immutable
class CanvasAiStagedContent {
  const CanvasAiStagedContent({
    this.nodeIds = const <String>[],
    this.edgeIds = const <String>[],
  });

  static const CanvasAiStagedContent empty = CanvasAiStagedContent();

  final List<String> nodeIds;
  final List<String> edgeIds;

  bool get isEmpty => nodeIds.isEmpty && edgeIds.isEmpty;
}

/// 真实 AI 编辑画布的分镜导演。
///
/// 镜头先就位、内容后落下，每一步按真实工具调用串行执行。
///
/// **背压**：[onActivity] 返回的 Future 在这一步演完时才完成，canvas 工具写库后
/// 会等它再返回。批量处理一瞬间发起几十次调用时，调用被动画节奏拖成一个接一个，
/// 画面与数据库始终同步 —— 不需要攒拍、合并或按积压压缩节奏去「追进度」。
/// 工具侧另有单次等待上限与取消放行，UI 卡住不会拖住 AI 回合；一轮放慢的总时长
/// 也有 [_roundBudget] 封顶。
///
/// 为什么还要藏内容：DB stream 回流到挂载有一两帧延迟，节点又要等镜头就位后才
/// 露面。先藏后揭，入场动效才能在镜头到位后播放（flow 的 `NodeContainer` 在
/// 转可见时重建子树，入场天然只播一次）。藏起来的只是正在演的这一步，用户一动手
/// [handOver] 立刻全揭，页面卸载/整图重载也一律回到「全部可见」。可见性只是
/// controller 的 UI 态，DB 不受影响。
///
/// 用户接管只交出镜头，节奏照旧：数据本来就与画面同步，剩下的调用跑快跑慢只影响
/// AI 多久写完；点一下画布就让剩余节点成片冒出来，反而回到一团糟的观感。
class CanvasAiDirector extends ChangeNotifier {
  CanvasAiDirector({required this.canvasId});

  final String canvasId;

  /// 节点即将露面前的回调。board 用它开入场动效窗口（`recentEntryNodeIds`）。
  ///
  /// 必须在 `setNodeVisibility(true)` **之前**调用：节点是在转可见那一帧首次
  /// 挂载的，那时读不到 id 就不播入场。
  void Function(String nodeId)? onNodeWillReveal;

  CanvasFlowController? _controller;
  bool _disposed = false;

  /// 镜头是否仍归导演。用户一动手就交出去；节奏不受影响。
  bool _following = true;

  // ---- 步子 ----

  /// 等待播放的步子（含正在播的那一步之后的全部）。
  final Queue<_AiStep> _queue = Queue<_AiStep>();
  _AiStep? _playing;
  bool _draining = false;

  // ---- 一轮跟随 ----

  /// 本轮锁定的缩放。首次取景时定下，收尾后清空 —— 一轮里只平移不缩放。
  double? _roundZoom;

  /// 本轮已经为节奏付出的等待时长。超过 [_roundBudget] 后不再等，直接揭示。
  Duration _roundSpent = Duration.zero;

  // ---- 已藏起、等待揭示 ----

  final Set<String> _hiddenNodeIds = <String>{};
  final Set<String> _hiddenEdgeIds = <String>{};

  /// 正在生长的连线 —— 用户中途接管时要一次性收尾，否则箭头会一直缺着。
  final Map<
    String,
    ({CanvasEdgeGrowEffect effect, flow.ConnectionEndPoint? endPoint})
  >
  _growing = {};

  // ---- 状态条 ----

  final Set<CanvasAiActivityKind> _statusKinds = <CanvasAiActivityKind>{};
  bool _statusVisible = false;
  Timer? _statusHideTimer;

  // ---- 焦点环 ----

  final Map<String, int> _focusStamps = <String, int>{};
  int _stamp = 0;

  // ---- 调度 ----

  Timer? _settleTimer;
  Timer? _stepTimer;
  Completer<void>? _sleeper;
  bool _notifyScheduled = false;

  /// 镜头是否仍在跟随 AI。
  bool get isFollowing => _following;

  /// 状态条是否可见（最后一次活动之后 [_statusHideDelay] 淡出）。
  bool get statusVisible => _statusVisible;

  /// 本轮唯一的操作类型；出现多种写操作时返回 null，由 UI 显示聚合文案。
  CanvasAiActivityKind? get statusKind {
    final writes = _writeKinds;
    if (writes.isEmpty) {
      return _statusKinds.isEmpty ? null : CanvasAiActivityKind.scan;
    }
    return writes.length == 1 ? writes.first : null;
  }

  /// 本轮出现了多种写操作 —— 状态条改说「正在编辑画布」。
  bool get isMultiKind => _writeKinds.length > 1;

  /// nodeId → 点亮序号。焦点环靠它判断「这个环是新的还是已经在淡出的」。
  Map<String, int> get focusStamps => UnmodifiableMapView(_focusStamps);

  Set<CanvasAiActivityKind> get _writeKinds =>
      _statusKinds.where((kind) => kind != CanvasAiActivityKind.scan).toSet();

  /// 接上画布，接收 board 转发的内容变更。
  void attach(CanvasFlowController controller) {
    _controller = controller;
  }

  /// 摘掉画布：先把藏起来的内容全部揭示，再清空排期并放行所有等待中的工具。
  void detach() {
    revealAll();
    _resetSchedule();
    _controller = null;
  }

  /// 收到一条 AI 活动事件，返回这一步演完的时刻。
  ///
  /// 只读事件（scan）只更新状态条、立刻放行；写事件排成一步，按到达顺序播放。
  Future<void> onActivity(CanvasAiActivity activity) {
    final controller = _controller;
    if (_disposed || controller == null || activity.canvasId != canvasId) {
      return Future<void>.value();
    }
    _statusKinds.add(activity.kind);
    _showStatus();
    _scheduleNotify();
    if (activity.isReadOnly) {
      return Future<void>.value();
    }

    final step = _AiStep();
    switch (activity.kind) {
      case CanvasAiActivityKind.add_node:
        for (final id in activity.focusNodeIds) {
          // DB stream 比事件先到、节点已经自己露面了：只给镜头与环。
          if (controller.getNode(id) != null) {
            step.touchedNodeIds.add(id);
          } else {
            step.awaitingNodeIds.add(id);
          }
        }
      case CanvasAiActivityKind.add_edge:
        // 边 id 不在事件里（事件报的是两端节点），只能按「这一步之后新出现的边」接管。
        // 两端不点环：连线自己会生长，再给两端各亮一圈，每条线都闪两下。
        step.awaitingEdges = true;
        step.edgeEndpointIds.addAll(activity.focusNodeIds);
      case CanvasAiActivityKind.update_node:
      case CanvasAiActivityKind.remove_node:
      case CanvasAiActivityKind.remove_edge:
      case CanvasAiActivityKind.auto_layout:
      case CanvasAiActivityKind.scan:
      // 新建/打开画布是宿主层的导航动作，没有可跟随的画面焦点。
      case CanvasAiActivityKind.create_canvas:
      case CanvasAiActivityKind.open_canvas:
        step.touchedNodeIds.addAll(activity.focusNodeIds);
    }
    _queue.add(step);
    _cancelSettle();
    unawaited(_drain());
    return step.done.future;
  }

  /// 增量挂载刚进 controller 的内容，返回被本导演接管（已置为不可见）的部分。
  ///
  /// **必须在节点/边已经 add 进 controller 之后同步调用**：藏与挂在同一帧内完成，
  /// 中间没有一帧是可见的，所以不会闪。
  ///
  /// 只接管 AI 写的内容：节点按 add_node 事件报上来的 id 精确匹配，用户自己加的
  /// 节点不会被藏（点一下工具栏却要等一步才出现是不可接受的）。边的 id 不在事件
  /// 里，交给最早一个还在等边的 add_edge 步。镜头已经交还时只认领、不藏 ——
  /// 内容照常立刻出现，这一步只负责节奏。
  CanvasAiStagedContent stageIncremental({
    required List<String> addedNodeIds,
    required List<String> addedEdgeIds,
  }) {
    if (_disposed || _controller == null) {
      return CanvasAiStagedContent.empty;
    }
    final nodeIds = <String>[];
    final edgeIds = <String>[];
    var remainingEdges = addedEdgeIds;
    for (final step in _pendingSteps) {
      for (final id in addedNodeIds) {
        if (step.awaitingNodeIds.remove(id)) {
          step.revealNodeIds.add(id);
          nodeIds.add(id);
        }
      }
      if (step.awaitingEdges && remainingEdges.isNotEmpty) {
        step.awaitingEdges = false;
        step.revealEdgeIds.addAll(remainingEdges);
        edgeIds.addAll(remainingEdges);
        remainingEdges = const <String>[];
      }
      step.signalIfStaged();
    }
    if (!_following || (nodeIds.isEmpty && edgeIds.isEmpty)) {
      return CanvasAiStagedContent.empty;
    }
    _hide(nodeIds: nodeIds, edgeIds: edgeIds);
    return CanvasAiStagedContent(nodeIds: nodeIds, edgeIds: edgeIds);
  }

  /// 整图重载（字段修改、换肤、切画布）后调用。
  ///
  /// `loadGraph` 会重建所有节点，隐藏态随之消失 —— 排期里的揭示已经没有对象。
  /// 内容既然已经在画面上了，镜头与高亮环仍然要给：待揭示和还在等回流的节点
  /// 都降级成「触碰」，这一步照样推镜头、照样点环，只是省掉了登场动作。
  void onGraphReloaded() {
    _hiddenNodeIds.clear();
    _hiddenEdgeIds.clear();
    for (final entry in _growing.values) {
      entry.effect.stop();
    }
    _growing.clear();
    for (final step in _pendingSteps) {
      step.demoteReveals();
      step.signalIfStaged();
    }
  }

  /// 用户接管：立刻揭示全部内容、把镜头交还。节奏照旧，见类注释。
  void handOver() {
    if (!_following) {
      return;
    }
    _following = false;
    _cancelSettle();
    // 叫醒正在飞的镜头等待：镜头已经不归导演，没必要让这一步继续等它。
    _cancelSleep();
    revealAll();
    _scheduleNotify();
  }

  /// 状态条上的跟随开关。
  void setFollowing(bool value) {
    if (value == _following) {
      return;
    }
    if (!value) {
      handOver();
      return;
    }
    _following = true;
    _scheduleSettle();
    _scheduleNotify();
  }

  /// 立刻揭示全部被藏起来的内容（不带镜头动作）。
  void revealAll() {
    final controller = _controller;
    // 先把长到一半的连线收尾，再统一揭示 —— 否则它们的箭头会一直缺着。
    for (final entry in _growing.entries) {
      entry.value.effect.stop();
      _settleEdge(entry.key, entry.value.effect, entry.value.endPoint);
    }
    _growing.clear();
    if (controller != null) {
      if (_hiddenNodeIds.isNotEmpty) {
        controller.setNodesVisibility(_hiddenNodeIds.toList(), true);
      }
      for (final edgeId in _hiddenEdgeIds) {
        final connection = controller.getConnection(edgeId);
        if (connection == null) {
          continue;
        }
        connection.visible = true;
        // 补齐时不再演生长动画：用户已经在等着操作了。
        connection.animationEffect = null;
      }
    }
    _hiddenNodeIds.clear();
    _hiddenEdgeIds.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _resetSchedule();
    _statusHideTimer?.cancel();
    _statusHideTimer = null;
    for (final entry in _growing.values) {
      entry.effect.stop();
    }
    _growing.clear();
    _hiddenNodeIds.clear();
    _hiddenEdgeIds.clear();
    _controller = null;
    super.dispose();
  }

  // ---- 播放 ----

  /// 还会消费挂载内容的步子：正在播的（可能还在等回流）加上排队的。
  Iterable<_AiStep> get _pendingSteps sync* {
    final playing = _playing;
    if (playing != null) {
      yield playing;
    }
    yield* _queue;
  }

  Future<void> _drain() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final step = _queue.removeFirst();
        _playing = step;
        try {
          await _playStep(step);
        } finally {
          _playing = null;
          step.release();
        }
      }
    } finally {
      _draining = false;
    }
    if (!_disposed) {
      _scheduleSettle();
    }
  }

  Future<void> _playStep(_AiStep step) async {
    // 工具写完库、内容还在经 DB stream 回流：等它挂进 controller，镜头才有落点。
    await step.waitStaged(_stageTimeout);
    if (_disposed) {
      return;
    }
    // 没等到回流（用户正拖着节点、整图重载吞掉了增量）：已经露面的照样给镜头与环。
    step.settleAwaiting(_controller);

    final paced = _roundSpent < _roundBudget;

    // 镜头先就位，内容后落下 —— 反过来会看到节点在画面外冒出来再被追上。
    if (_following && _moveCamera(step) && paced) {
      await _pace(_cameraDuration);
      if (_disposed) {
        return;
      }
    }
    // 修改类操作没有揭示动作，环在镜头到位时点亮。
    for (final nodeId in step.touchedNodeIds) {
      _markFocus(nodeId);
    }
    for (final nodeId in step.revealNodeIds) {
      _revealNode(nodeId);
    }
    for (final edgeId in step.revealEdgeIds) {
      _revealEdge(edgeId);
    }
    if (paced) {
      await _pace(_stepInterval);
    }
  }

  /// 计入本轮预算的等待。
  Future<void> _pace(Duration duration) {
    _roundSpent += duration;
    return _sleep(duration);
  }

  /// 按这一步的焦点决定镜头动作，返回是否真的动了。
  ///
  /// [step] 为 null 表示一轮收尾。一轮里第一次取景时锁定缩放，之后只平移；
  /// 没有焦点的步子（删除、整理布局）中途不动镜头，留给收尾统一收敛。
  bool _moveCamera(_AiStep? step) {
    final controller = _controller;
    if (controller == null) {
      return false;
    }
    final screen = controller.screenSize;
    if (screen.isEmpty) {
      return false;
    }

    Rect? rectOf(String id) {
      final node = controller.getNode(id);
      return node == null ? null : node.position.value & node.size.value;
    }

    Rect? focus;
    if (step != null) {
      for (final id in <String>{
        ...step.revealNodeIds,
        ...step.touchedNodeIds,
      }) {
        final rect = rectOf(id);
        if (rect == null) {
          continue;
        }
        focus = focus == null ? rect : focus.expandToInclude(rect);
      }
      if (focus == null && step.edgeEndpointIds.isNotEmpty) {
        focus = canvasEdgeFocus(
          visibleBounds: controller.visibleGraphBounds,
          endpoints: [for (final id in step.edgeEndpointIds) ?rectOf(id)],
        );
      }
      if (focus == null) {
        return false;
      }
    }

    final settled = focus == null;
    final currentZoom = controller.viewport.zoom;
    var command = decideCanvasCamera(
      screenSize: screen,
      currentZoom: currentZoom,
      visibleBounds: controller.visibleGraphBounds,
      contentBounds: controller.nodesBounds,
      focusBounds: focus,
      settled: settled,
      minZoom: controller.config.minZoom.value,
      maxZoom: controller.config.maxZoom.value,
      lockedZoom: settled ? null : _roundZoom,
    );
    if (!settled && _roundZoom == null) {
      final zoom = canvasFollowZoomFor(
        command is CanvasCameraMove ? command.zoom : currentZoom,
      );
      _roundZoom = zoom;
      if (command is CanvasCameraMove) {
        command = CanvasCameraMove(center: command.center, zoom: zoom);
      }
    }
    if (command is! CanvasCameraMove) {
      return false;
    }
    controller.animateToViewport(
      flow.GraphViewport(
        x: screen.width / 2 - command.center.dx * command.zoom,
        y: screen.height / 2 - command.center.dy * command.zoom,
        zoom: command.zoom,
      ),
      duration: settled ? _settleCameraDuration : _cameraDuration,
      curve: Curves.easeInOutCubic,
    );
    return true;
  }

  void _revealNode(String nodeId) {
    if (!_hiddenNodeIds.remove(nodeId)) {
      // 已经可见（整图重载抹掉了隐藏态、或镜头已交还没藏）：只补一圈环。
      _markFocus(nodeId);
      return;
    }
    onNodeWillReveal?.call(nodeId);
    _controller?.setNodeVisibility(nodeId, true);
    _markFocus(nodeId);
  }

  void _revealEdge(String edgeId) {
    // 没藏过的边已经由 board 立刻显示并生长过了。
    if (!_hiddenEdgeIds.remove(edgeId)) {
      return;
    }
    final connection = _controller?.getConnection(edgeId);
    if (connection == null) {
      return;
    }
    connection.visible = true;
    _growEdge(connection);
  }

  /// 新边生长：挂上动效并暂时藏起箭头，长完装回。
  ///
  /// 箭头由 painter 在 effect 之外无条件绘制，不藏会看到一枚箭头孤零零悬在
  /// 终点、线才慢慢追过去。摘 effect 是硬要求 —— 留着它，这条边会让整张画布
  /// 常驻 60fps 重绘。
  void _growEdge(CanvasFlowConnection connection) {
    final restoreEndPoint = connection.endPoint;
    if (restoreEndPoint != null &&
        restoreEndPoint.shape != flow.MarkerShapes.none) {
      connection.endPoint = _hiddenEndPoint;
    }
    final effect = CanvasEdgeGrowEffect();
    connection.animationEffect = effect;
    _growing[connection.id] = (effect: effect, endPoint: restoreEndPoint);
    effect.start(
      onDone: () {
        _growing.remove(connection.id);
        _settleEdge(connection.id, effect, restoreEndPoint);
      },
    );
  }

  void _settleEdge(
    String edgeId,
    CanvasEdgeGrowEffect effect,
    flow.ConnectionEndPoint? endPoint,
  ) {
    final connection = _controller?.getConnection(edgeId);
    if (connection == null) {
      return;
    }
    connection.endPoint = endPoint;
    if (connection.animationEffect == effect) {
      connection.animationEffect = null;
    }
  }

  void _hide({required List<String> nodeIds, required List<String> edgeIds}) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (nodeIds.isNotEmpty) {
      controller.setNodesVisibility(nodeIds, false);
      _hiddenNodeIds.addAll(nodeIds);
    }
    for (final edgeId in edgeIds) {
      final connection = controller.getConnection(edgeId);
      if (connection == null) {
        continue;
      }
      connection.visible = false;
      _hiddenEdgeIds.add(edgeId);
    }
  }

  void _markFocus(String nodeId) {
    _stamp += 1;
    _focusStamps[nodeId] = _stamp;
    if (_focusStamps.length > _maxRings) {
      final ordered = _focusStamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in ordered.take(_focusStamps.length - _maxRings)) {
        _focusStamps.remove(entry.key);
      }
    }
    _scheduleNotify();
  }

  // ---- 收尾与状态条 ----

  /// 一轮活动停下来之后补一次收敛，并结束这一轮（解锁缩放、清空预算）。
  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () {
      _settleTimer = null;
      if (_disposed || _queue.isNotEmpty || _playing != null) {
        return;
      }
      if (_following) {
        _moveCamera(null);
      }
      _roundZoom = null;
      _roundSpent = Duration.zero;
    });
  }

  void _cancelSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  void _showStatus() {
    _statusVisible = true;
    _statusHideTimer?.cancel();
    _statusHideTimer = Timer(_statusHideDelay, () {
      _statusHideTimer = null;
      _statusVisible = false;
      _statusKinds.clear();
      _scheduleNotify();
    });
  }

  // ---- 调度基础设施 ----

  /// 清空排期并放行所有等待中的工具。只在 detach / dispose 时调用。
  void _resetSchedule() {
    for (final step in _pendingSteps) {
      step.release();
    }
    _queue.clear();
    _cancelSettle();
    _cancelSleep();
  }

  /// 可打断的等待。[handOver] / [dispose] 会立刻把它唤醒，不留悬空 Timer。
  Future<void> _sleep(Duration duration) {
    _cancelSleep();
    if (duration <= Duration.zero) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _sleeper = completer;
    _stepTimer = Timer(duration, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  void _cancelSleep() {
    _stepTimer?.cancel();
    _stepTimer = null;
    final sleeper = _sleeper;
    _sleeper = null;
    if (sleeper != null && !sleeper.isCompleted) {
      sleeper.complete();
    }
  }

  /// 合并一次 notify 到微任务。
  ///
  /// [stageIncremental] / [onGraphReloaded] 由 board 的 `useEffect` 在 build 期
  /// 同步调用，此时直接 notifyListeners 会让监听方在 build 中 markNeedsBuild。
  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_disposed) {
        return;
      }
      notifyListeners();
    });
  }
}

/// 一步：一次写工具调用对应的镜头焦点 + 揭示内容。
class _AiStep {
  /// 演完（或被放行）时完成。工具 await 它实现背压。
  final Completer<void> done = Completer<void>();

  /// add_node 已经报上来、但内容还没经 DB stream 回流挂载的节点 id。
  final Set<String> awaitingNodeIds = <String>{};

  /// add_edge 报上来了，新边还没挂载。
  bool awaitingEdges = false;

  final List<String> revealNodeIds = <String>[];
  final List<String> revealEdgeIds = <String>[];

  /// 被修改/删除触碰、但不需要揭示的节点（只进镜头焦点与高亮环）。
  final Set<String> touchedNodeIds = <String>{};

  /// 新连线的两端（起点, 终点）。只用来判断要不要追镜头，不点环。
  final List<String> edgeEndpointIds = <String>[];

  Completer<void>? _staged;
  Timer? _stageTimer;

  bool get isStaged => awaitingNodeIds.isEmpty && !awaitingEdges;

  /// 等内容回流，最多等 [timeout]。
  Future<void> waitStaged(Duration timeout) {
    if (isStaged) {
      return Future<void>.value();
    }
    final completer = _staged = Completer<void>();
    _stageTimer = Timer(timeout, _wake);
    return completer.future;
  }

  void signalIfStaged() {
    if (isStaged) {
      _wake();
    }
  }

  /// 不再等回流：已经露面的节点降级成触碰，其余作罢。
  void settleAwaiting(CanvasFlowController? controller) {
    for (final id in awaitingNodeIds) {
      if (controller?.getNode(id) != null) {
        touchedNodeIds.add(id);
      }
    }
    awaitingNodeIds.clear();
    awaitingEdges = false;
  }

  /// 待揭示内容已经被整图重载放出来了：降级成只进镜头与高亮环的「触碰」。
  void demoteReveals() {
    touchedNodeIds
      ..addAll(revealNodeIds)
      ..addAll(awaitingNodeIds);
    revealNodeIds.clear();
    revealEdgeIds.clear();
    awaitingNodeIds.clear();
    awaitingEdges = false;
  }

  /// 放行等待这一步的工具（演完、或排期被清空）。
  void release() {
    _wake();
    if (!done.isCompleted) {
      done.complete();
    }
  }

  void _wake() {
    _stageTimer?.cancel();
    _stageTimer = null;
    final staged = _staged;
    _staged = null;
    if (staged != null && !staged.isCompleted) {
      staged.complete();
    }
  }
}

/// 每一步揭示后的间隔。
const Duration _stepInterval = Duration(milliseconds: 150);

/// 跟随镜头单次平移的时长。
const Duration _cameraDuration = Duration(milliseconds: 520);

/// 等内容经 DB stream 回流挂载的上限。
const Duration _stageTimeout = Duration(milliseconds: 600);

/// 一轮最多为节奏付出的等待。超过后不再等，几百次调用的批量也不会被拖到超时。
const Duration _roundBudget = Duration(seconds: 10);

/// 一轮活动停下之后补收敛镜头的延迟。
const Duration _settleDelay = Duration(milliseconds: 1200);
const Duration _settleCameraDuration = Duration(milliseconds: 560);

/// 状态条在最后一次活动之后的驻留时长。
const Duration _statusHideDelay = Duration(milliseconds: 1500);

/// 同屏最多保留的焦点环数量，避免几十个环一起重绘。
const int _maxRings = 12;

/// 生长期间临时替换上去的「无箭头」端点。
const flow.ConnectionEndPoint _hiddenEndPoint = flow.ConnectionEndPoint(
  shape: flow.MarkerShapes.none,
  size: Size.zero,
);
