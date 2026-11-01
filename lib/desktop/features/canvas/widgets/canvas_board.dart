// 职责: 画布工作区核心 — 渲染 NodeFlowEditor、DB↔flow 双向同步、连线落点拦截与原地编辑回调
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/desktop/features/canvas/widgets/canvas_edge_grow_effect.dart
//   lib/desktop/features/canvas/widgets/canvas_edge_flow_highlight.dart
//   lib/desktop/features/canvas/widgets/canvas_ai_focus_layer.dart
//   lib/desktop/features/canvas/canvas_ai_director.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/widgets/app_background.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/error-handling.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/providers/canvas_providers.dart';
import '../../../../shared/services/canvas_service.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../canvas_ai_director.dart';
import '../canvas_palette.dart';
import '../edit_session.dart';
import '../layout_menu.dart';
import 'canvas_ai_focus_layer.dart';
import 'canvas_ai_status_pill.dart';
import 'canvas_detail_layer.dart';
import 'canvas_edge_flow_highlight.dart';
import 'canvas_edge_grow_effect.dart';
import 'canvas_flow_adapter.dart';
import 'canvas_node_widget.dart';
import 'floating_cluster.dart';
import 'zoom_control.dart';

/// 画布工作区：DB 是唯一真相源，flow Controller 是 UI 状态。
///
/// - 外部写入(agent/DB stream) → `isSyncingFromProps` 置位 → 整图 loadGraph
///   或纯增删时的增量挂载([diffCanvasContent]) → 忽略此期间 flow 事件。
/// - 用户拖拽/连线 → flow 事件回调 → CanvasService 写回 DB(防循环)。
/// - 连线落点不直接落库：先撤销库建的乐观连线，弹类型选择卡，选定后才写 DB。
/// - 选中节点/连线的原地编辑面板由 [CanvasDetailLayer] 在编辑器同级前景层渲染。
/// - AI 写入的内容不直接现身：交给 [CanvasAiDirector] 藏起来排队，镜头就位后
///   逐个揭示。board 只负责把「新内容挂上了」「用户动手了」转告导演。
///
/// controller 与 detailLayer 由 [CanvasRegion] 创建并传入。
class CanvasBoard extends HookConsumerWidget {
  const CanvasBoard({
    super.key,
    required this.canvasId,
    required this.databasePath,
    required this.controller,
    required this.detailLayer,
    required this.focusLayer,
    this.invalidNodeIds = const <String>{},
    this.onAddReference,
    this.onAddSticky,
    this.onAutoLayout,
    this.exportControl,
    this.onLayout,
    this.editSession,
    this.onCleanDead,
    this.onOpenScene,
    this.editable = true,
    this.onEditBlocked,
  });

  final String canvasId;
  final String databasePath;
  final CanvasFlowController controller;

  /// 原地编辑浮层 plugin(随 controller 一同创建并注册)。
  final CanvasDetailLayer detailLayer;

  /// AI 焦点高亮浮层 plugin(随 controller 一同创建并注册)。
  final CanvasAiFocusLayer focusLayer;

  /// 引用已失效(资源被删)的节点 id 集合,用于渲染灰态。
  /// 由 [CanvasRegion] watch `canvasInvalidNodeIdsProvider` 后传入。
  final Set<String> invalidNodeIds;

  /// 添加资源引用节点到画布中心。
  final VoidCallback? onAddReference;

  /// 添加空白便签到画布中心。
  final VoidCallback? onAddSticky;

  /// 按连线关系自动整理布局。
  final VoidCallback? onAutoLayout;
  final Widget? exportControl;
  final Future<void> Function(String)? onLayout;
  final CanvasEditSession? editSession;

  /// 清理所有失效引用节点。
  final VoidCallback? onCleanDead;
  final ValueChanged<String>? onOpenScene;

  /// 免费态只读：false 时画布进入 inspect 行为（可看/可选/可缩放，不可拖拽/
  /// 连线/删除），原地编辑回调统一改写为 [onEditBlocked]。
  final bool editable;

  /// 只读态下用户尝试编辑（改便签/删节点/改连线）时触发 —— 由页面层弹升级引导。
  final VoidCallback? onEditBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);
    final isSyncingFromProps = useRef(false);
    final didLoadInitial = useRef(false);
    final loadedCanvasId = useRef<String?>(null);
    final lastContent =
        useRef<({List<CanvasNode> nodes, List<CanvasEdge> edges})?>(null);
    final lastInvalidNodeIds = useRef<Set<String>>(const <String>{});
    final lastColors = useRef<RevericColors?>(null);
    final lastLayout = useRef<String?>(null);
    final prevSelectedNodeIds = useRef<Set<String>>(const <String>{});

    /// 选中节点的出边流动高亮。选中态变化、连线增删/重载后都要 [sync] 一次。
    final edgeHighlight = useMemoized(
      () => CanvasEdgeFlowHighlight(color: colors.accent),
      [controller],
    );
    edgeHighlight.color = colors.accent;

    /// 已撤销的乐观连线 id：库在落点处会先建连线，我们撤掉它以改为「先选类型」，
    /// 这些 id 触发的 onDeleted 不是用户删边，须跳过写库。
    final optimisticEdgeIds = useRef<Set<String>>(const <String>{});

    /// 刚由增量挂载加进来的节点 id(入场动效窗口)。
    ///
    /// 入场动画在节点 widget 首次挂载时播放;id 只在这个窗口期内留在集合里,
    /// 之后节点滚出视口再回来(库会卸载屏外节点)不会重复播。
    final recentEntryNodeIds = useRef<Set<String>>(<String>{});

    /// 待选类型的连线；非空时由详情层渲染类型选择卡。
    final pendingEdge = useState<CanvasPendingEdge?>(null);

    /// AI 编辑的分镜导演。
    ///
    /// 镜头、内容揭示节奏、焦点环、状态条文案全部归它；board 只负责把
    /// 「新内容挂上了」和「用户动手了」这两件事告诉它。
    final aiDirector = useMemoized(() => CanvasAiDirector(canvasId: canvasId), [
      canvasId,
      controller,
    ]);
    useEffect(() => aiDirector.dispose, [aiDirector]);
    useEffect(() {
      aiDirector.attach(controller);
      return aiDirector.detach;
    }, [aiDirector, controller]);

    /// 开一次入场动效窗口。
    ///
    /// 入场靠「节点首次构建即播放」触发，所以 id 必须在节点挂载/转可见的那一刻
    /// 就在集合里。被导演藏起来的节点由它在揭示前回调，普通新增则挂载时立刻开窗。
    void openEntryWindow(String nodeId) {
      recentEntryNodeIds.value.add(nodeId);
      Timer(_recentEntryWindow, () {
        recentEntryNodeIds.value.remove(nodeId);
      });
    }

    aiDirector.onNodeWillReveal = openEntryWindow;

    // 监听 DB 内容 stream，外部写入同步到 flow controller。
    final contentAsync = ref.watch(
      canvasContentStreamProvider((
        canvasId: canvasId,
        databasePath: databasePath,
      )),
    );
    final layout = ref.watch(
      canvasEntryProvider((
        canvasId: canvasId,
        databasePath: databasePath,
      )).select((entry) => entry.value?.layout),
    );

    /// 新边生长:挂上动效并暂时藏起箭头,长完装回。
    ///
    /// 箭头由 painter 在 effect 之外无条件绘制,不藏会看到一枚箭头孤零零悬在
    /// 终点、线才慢慢追过去。摘 effect 是硬要求 —— 留着它,这条边会让整张
    /// 画布常驻 60fps 重绘。
    void startEdgeGrow(CanvasFlowConnection connection) {
      final restoreEndPoint = connection.endPoint;
      final effect = CanvasEdgeGrowEffect();
      connection.animationEffect = effect;
      if (restoreEndPoint != null &&
          restoreEndPoint.shape != flow.MarkerShapes.none) {
        connection.endPoint = const flow.ConnectionEndPoint(
          shape: flow.MarkerShapes.none,
          size: Size.zero,
        );
      }
      effect.start(
        onDone: () {
          if (controller.getConnection(connection.id) == null) {
            return;
          }
          connection.endPoint = restoreEndPoint;
          if (connection.animationEffect == effect) {
            connection.animationEffect = null;
          }
          // 生长期间高亮让位，长完再按选中态补上。
          edgeHighlight.sync(controller);
        },
      );
    }

    /// 增量应用内容差集(仅限纯增删):新节点播入场、新边生长,其余原地不动。
    ///
    /// 事件防护与整图重载同款:add/remove 会触发 flow 事件(onCreated/
    /// onDeleted),isSyncingFromProps 置位期间这些回调不写库,帧后解除。
    void applyIncrementalDiff(
      CanvasContentDiff diff,
      ({List<CanvasNode> nodes, List<CanvasEdge> edges}) content,
    ) {
      isSyncingFromProps.value = true;
      // 先删节点:removeNode 会级联摘掉挂在它身上的连线。
      for (final nodeId in diff.removedNodeIds) {
        controller.removeNode(nodeId);
      }
      for (final edgeId in diff.removedEdgeIds) {
        final connection = controller.getConnection(edgeId);
        // 已随节点删除被级联摘掉的不能重复删(removeConnection 对缺失 id 会抛)。
        if (connection == null) {
          continue;
        }
        (connection.animationEffect as CanvasEdgeGrowEffect?)?.stop();
        controller.removeConnection(edgeId);
      }
      final nodeById = {for (final node in content.nodes) node.id: node};
      final mountedNodeIds = <String>[];
      final mountedEdges = <CanvasFlowConnection>[];
      for (final node in diff.addedNodes) {
        if (controller.getNode(node.id) != null) {
          continue;
        }
        controller.addNode(
          canvasNodeToFlowNode(
            node,
            colors: colors,
            isInvalid: invalidNodeIds.contains(node.id),
          ),
        );
        mountedNodeIds.add(node.id);
      }
      for (final edge in diff.addedEdges) {
        final source = nodeById[edge.sourceNodeId];
        final target = nodeById[edge.targetNodeId];
        // 端点不在内容里的边,与整图构建同策略:跳过。
        if (source == null || target == null) {
          continue;
        }
        if (controller.getConnection(edge.id) != null) {
          continue;
        }
        final connection = canvasEdgeToFlowConnection(
          edge,
          colors: colors,
          sourceCenter: canvasNodeCenter(source),
          targetCenter: canvasNodeCenter(target),
          layout: layout,
        );
        controller.addConnection(connection);
        mountedEdges.add(connection);
      }

      // 交给导演挑走 AI 写的那部分：它会在同一帧内把这些节点/边置为不可见，
      // 等镜头就位后再逐个揭示。中间没有一帧是可见的，所以不会闪。
      // 剩下的（用户加的便签、用户拖出来的连线）照旧立刻现身。
      final staged = aiDirector.stageIncremental(
        addedNodeIds: mountedNodeIds,
        addedEdgeIds: [for (final connection in mountedEdges) connection.id],
      );
      for (final nodeId in mountedNodeIds) {
        if (!staged.nodeIds.contains(nodeId)) {
          openEntryWindow(nodeId);
        }
      }
      for (final connection in mountedEdges) {
        if (!staged.edgeIds.contains(connection.id)) {
          startEdgeGrow(connection);
        }
      }
      edgeHighlight.sync(controller);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        isSyncingFromProps.value = false;
      });
    }

    useEffect(
      () {
        final content = contentAsync.asData?.value;
        if (editSession?.hasInteractions ?? false) {
          return null;
        }
        if (content == null) {
          return null;
        }
        // 跳过同引用的重复发射(仅初次加载或 canvas 切换时实际 load)。
        // invalidNodeIds 变化(资源被删/恢复)也需重载以刷新灰态。
        // 主题换肤时内容签名不变,但边色/纸色由 colors 派生,故也需重载。
        final invalidChanged =
            lastInvalidNodeIds.value.length != invalidNodeIds.length ||
            !lastInvalidNodeIds.value.containsAll(invalidNodeIds);
        final colorsChanged = lastColors.value != colors;
        final layoutChanged = lastLayout.value != layout;
        final shouldLoad =
            !didLoadInitial.value ||
            loadedCanvasId.value != canvasId ||
            !sameCanvasContentSignature(lastContent.value, content) ||
            invalidChanged ||
            colorsChanged ||
            layoutChanged;
        final previousContent = lastContent.value;
        lastContent.value = content;
        lastInvalidNodeIds.value = invalidNodeIds;
        lastColors.value = colors;
        lastLayout.value = layout;
        if (!shouldLoad) {
          return null;
        }
        // 增量挂载:同一张画布上纯增删(AI 逐条加节点/边、用户增删)时,只挂
        // 新增、摘删除,视口与选中态原地不动 —— 新节点才能播入场、新边才能
        // 生长;整图重载会重建所有节点,全员重弹入场正是普通画布此前不敢开
        // 入场动效的原因。带字段修改(拖拽落点、便签编辑、自动重排、边改
        // 类型)、首载、切画布、失效集或主题变化时仍走整图重载。
        final previous = previousContent;
        if (didLoadInitial.value &&
            loadedCanvasId.value == canvasId &&
            !invalidChanged &&
            !colorsChanged &&
            !layoutChanged &&
            previous != null) {
          final diff = diffCanvasContent(previous, content);
          if (!diff.hasModifications) {
            applyIncrementalDiff(diff, content);
            return null;
          }
        }
        // 整图重载会重建所有节点，隐藏态随之消失 —— 导演排期里的揭示已经没有
        // 对象，必须先让它作废，否则 revealAll 会对着不存在的 id 空转。
        aiDirector.onGraphReloaded();
        final shouldPreserveViewport =
            didLoadInitial.value && loadedCanvasId.value == canvasId;
        final viewport = shouldPreserveViewport
            ? controller.exportGraph().viewport
            : const flow.GraphViewport();
        isSyncingFromProps.value = true;
        // loadGraph 会重置选中态。位置变化也会触发重载(拖拽结束、自动重排)，
        // 选中态若跟着丢，正在编辑的节点详情面板会当场消失 —— 载入后按 id 还原。
        final selectedBeforeLoad = shouldPreserveViewport
            ? controller.selectedNodeIds.toSet()
            : const <String>{};
        prevSelectedNodeIds.value = const <String>{};
        controller.loadGraph(
          canvasContentToFlowGraph(
            content.nodes,
            content.edges,
            colors: colors,
            invalidNodeIds: invalidNodeIds,
            viewport: viewport,
            layout: layout,
          ),
        );
        for (final id in selectedBeforeLoad) {
          if (controller.getNode(id) != null) {
            controller.selectNode(id, toggle: true);
          }
        }
        edgeHighlight.sync(controller);
        loadedCanvasId.value = canvasId;
        didLoadInitial.value = true;

        // 在下一帧解除标志位，避免 loadGraph 触发的 flow 事件被误当作用户操作回写。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          isSyncingFromProps.value = false;
          if (!shouldPreserveViewport) {
            controller.fitToView();
          }
        });
        return null;
      },
      [
        contentAsync,
        canvasId,
        controller,
        invalidNodeIds,
        colors,
        layout,
        editSession?.hasInteractions,
      ],
    );

    // ---- AI 编辑分镜 ----
    //
    // DB stream 只说明「内容变了」,分不出是 AI 写的还是用户拖的,也没有语义标签;
    // canvas 工具写库成功后经 canvasAiActivityProvider 广播的活动事件补上这两点。
    // 导演以节拍器身份直连 notifier:每条事件都送到(不经 watch 合帧),工具还会
    // 等这一步演完再返回。镜头、揭示节奏全部归 [CanvasAiDirector]。
    final activityNotifier = ref.read(canvasAiActivityProvider.notifier);

    useEffect(() {
      final CanvasAiPacer pacer = aiDirector.onActivity;
      activityNotifier.attachPacer(canvasId, pacer);
      return () => activityNotifier.detachPacer(canvasId, pacer);
    }, [activityNotifier, aiDirector, canvasId]);

    useEffect(() {
      return () {
        // 下次打开画布不该看到上一次残留的状态条。
        // cleanup 在 unmount 时同步执行,仍处于 build 阶段,直接写 provider 会
        // 触发 _debugCanModifyProviders 断言 —— 推迟到帧后(与
        // ActiveCanvasScope 的 clearIfActive 同款)。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            activityNotifier.clear();
          } catch (_) {}
        });
      };
    }, const <Object?>[]);

    // 焦点高亮:与 detailLayer 同款,build 期同步字段,由 plugin 在 overlays 层渲染。
    // 环随节点逐个揭示点亮,直接订阅导演 —— 走 board rebuild 会让整块画布跟着重建。
    focusLayer.director = aiDirector;

    // 选中节点提到最前，详情面板才不会被邻近节点压住。
    void handleSelection(
      flow.SelectionState<CanvasFlowNodeData, String> state,
    ) {
      final newSelectedIds = state.nodes.map((n) => n.id).toSet();
      for (final id in newSelectedIds.difference(prevSelectedNodeIds.value)) {
        controller.bringNodeToFront(id);
      }
      prevSelectedNodeIds.value = newSelectedIds;
      edgeHighlight.sync(controller);
    }

    final service = ref.read(canvasServiceProvider(databasePath));

    final events = useMemoized(
      () => flow.NodeFlowEvents<CanvasFlowNodeData, String>(
        node: flow.NodeEvents<CanvasFlowNodeData>(
          onDragCancel: (node) => editSession?.endInteraction(node.id),
          onResizeCancel: (node) => editSession?.endInteraction(node.id),
          onDragStop: (node) {
            if (editSession != null || !editable || isSyncingFromProps.value) {
              return;
            }
            final position = node.position.value;
            service.updateNodePosition(
              nodeId: node.id,
              x: position.dx,
              y: position.dy,
            );
          },
          onDeleted: (node) {
            if (!editable || isSyncingFromProps.value) return;
            if (editSession case final session?) {
              session.writeInBackground(
                'delete:${node.id}',
                () => service.softDeleteNode(node.id),
              );
            } else {
              unawaited(service.softDeleteNode(node.id));
            }
          },
        ),
        connection: flow.ConnectionEvents<CanvasFlowNodeData, String>(
          onCreated: (connection) {
            if (!editable || isSyncingFromProps.value) return;
            // 库在拖拽落点处立刻建好一条乐观连线，但「这条线是什么关系」是作者的
            // 判断——静默写一个泛化类型会让画布很快堆满无意义的关联线。因此这里
            // 撤掉乐观连线，弹出类型选择卡，选定后才由 CanvasService 落库、经
            // stream 回流成真正的边。
            final at = controller.interaction.pointerPosition?.offset;
            optimisticEdgeIds.value = {
              ...optimisticEdgeIds.value,
              connection.id,
            };
            controller.removeConnection(connection.id);
            if (at == null) {
              // 拿不到落点就无处弹层；直接放弃这次连线,不静默写库。
              return;
            }
            pendingEdge.value = CanvasPendingEdge(
              sourceNodeId: connection.sourceNodeId,
              targetNodeId: connection.targetNodeId,
              at: at,
            );
          },
          onDeleted: (connection) {
            if (!editable || isSyncingFromProps.value) return;
            // 上面撤销的乐观连线从未入库，不能当作用户删边。
            if (optimisticEdgeIds.value.contains(connection.id)) {
              optimisticEdgeIds.value = {...optimisticEdgeIds.value}
                ..remove(connection.id);
              return;
            }
            if (editSession case final session?) {
              session.writeInBackground(
                'delete:${connection.id}',
                () => service.hardDeleteEdge(connection.id),
              );
            } else {
              unawaited(service.hardDeleteEdge(connection.id));
            }
          },
          onBeforeComplete: (context) {
            if (!editable) {
              return const flow.ConnectionValidationResult.deny();
            }
            // 禁止自环；其余同 canvas anchor port 间允许自由连线。
            if (context.isSelfConnection) {
              return const flow.ConnectionValidationResult.deny();
            }
            return const flow.ConnectionValidationResult.allow();
          },
        ),
        onSelectionChange: handleSelection,
      ),
      [controller, service, canvasId, editable, editSession],
    );

    // 画布写入失败时给出可理解的提示；技术细节留在 service 的 [DB] 日志里。
    void showWriteError(Object error) {
      if (!context.mounted) return;
      final message = switch (error) {
        CanvasServiceException(errorCode: 'duplicate_edge') => context.t(
          LocaleKeys.canvasEdgeDuplicate,
        ),
        CanvasServiceException(errorCode: 'invalid_edge_semantics') =>
          context.t(LocaleKeys.canvasEdgeInvalidForeshadow),
        _ => context.t(LocaleKeys.commonSaveFailed),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    /// service 调用统一包一层：失败提示用户,不让异常静默消失。
    Future<void> write(String key, Future<void> Function() action) async {
      try {
        if (editSession case final session?) {
          await session.write(key, action);
        } else {
          await action();
        }
      } catch (error) {
        showWriteError(error);
        rethrow;
      }
    }

    void background(String key, Future<void> Function() action) {
      unawaited(write(key, action).catchError((Object _) {}));
    }

    if (editSession case final session?) {
      session.onWriteError = showWriteError;
      session.saveGeometry = (id, position, size) => service.updateNodeGeometry(
        nodeId: id,
        position: position,
        size: size,
      );
    }

    // 只读态下把所有编辑回调换成升级引导 —— 查看（选择/详情展开）保持可用。
    final blocked = onEditBlocked ?? () {};
    final callbacks = CanvasDetailCallbacks(
      onOpenScene: onOpenScene,
      editSession: editSession,
      onSelectNode: (nodeId) => controller.selectNode(nodeId),
      onDeleteNode: (nodeId) => editable
          ? background('delete:$nodeId', () => service.softDeleteNode(nodeId))
          : blocked(),
      onStickyTitleChanged: (nodeId, title) => editable
          ? write(
              'title:$nodeId',
              () => service.updateNodeTitle(nodeId: nodeId, title: title),
            )
          : Future.sync(blocked),
      onStickyContentChanged: (nodeId, content) => editable
          ? write(
              'content:$nodeId',
              () => service.updateNodeContent(nodeId: nodeId, content: content),
            )
          : Future.sync(blocked),
      onNodeColorChanged: (node, color) => editable
          ? background(
              'style:${node.id}',
              () => service.updateNodeStyle(
                nodeId: node.id,
                style: canvasStyleWithColor(node.style, color),
              ),
            )
          : blocked(),
      onEdgeTypeChanged: (edgeId, type) => editable
          ? background(
              'type:$edgeId',
              () => service.updateEdge(edgeId: edgeId, type: type),
            )
          : blocked(),
      onEdgeLabelChanged: (edgeId, label) => editable
          ? write(
              'label:$edgeId',
              () => service.updateEdge(edgeId: edgeId, label: label),
            )
          : Future.sync(blocked),
      onDeleteEdge: (edgeId) => editable
          ? background('delete:$edgeId', () => service.hardDeleteEdge(edgeId))
          : blocked(),
      onClearSelection: () => controller.clearSelection(),
      onPickPendingEdgeType: (type) {
        final pending = pendingEdge.value;
        pendingEdge.value = null;
        if (pending == null) return;
        background(
          'add-edge:${pending.sourceNodeId}:${pending.targetNodeId}',
          () => service.addEdge(
            canvasId: canvasId,
            sourceNodeId: pending.sourceNodeId,
            targetNodeId: pending.targetNodeId,
            type: type,
          ),
        );
      },
      onCancelPendingEdge: () => pendingEdge.value = null,
    );

    // plugin 是长生命周期对象，通过可变字段在 rebuild 时同步回调与内容快照，
    // 避免重注册 plugin。
    detailLayer
      ..callbacks = callbacks
      ..content =
          contentAsync.asData?.value ??
          (nodes: const <CanvasNode>[], edges: const <CanvasEdge>[])
      ..pendingEdge = pendingEdge.value;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: appChromeBackgroundColor(
          colors,
          appBackgroundActive,
          colors.canvas,
        ),
      ),
      child: Stack(
        children: [
          // 用户一动手就停跟随:正在看别处时被镜头拽走比不跟随更难受。
          // translucent + 只读监听,不吞任何手势。
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                // 用户一动手就把画面交出去 —— 并且立刻补齐剩余内容。
                aiDirector.handOver();
              },
              onPointerSignal: (_) {
                aiDirector.handOver();
              },
              child: flow.NodeFlowEditor<CanvasFlowNodeData, String>(
                key: ObjectKey(controller),
                controller: controller,
                theme: canvasFlowTheme(
                  colors,
                  RevericTheme.typographyOf(context),
                  appBackgroundActive,
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.fontFamily,
                ),
                // 免费态只读：inspect 允许查看/选中/缩放，禁掉拖拽/连线/删除。
                behavior: editable
                    ? flow.NodeFlowBehavior.design
                    : flow.NodeFlowBehavior.inspect,
                events: events,
                nodeBuilder: (context, node) => CanvasNodeCard(
                  node: node,
                  databasePath: databasePath,
                  // 仅新增节点在入场窗口内播放动画。
                  animateEntry: recentEntryNodeIds.value.contains(node.id),
                ),
              ),
            ),
          ),
          // 详情面板必须在 NodeFlowEditor 之外：编辑器根 Listener 会把其内部点击
          // 视为画布空白点击并清选中态，导致便签输入框刚点开就消失。
          detailLayer.buildOverlay(
            controller,
            databasePath: databasePath,
            ignoreInput: editSession?.editingLocked ?? false,
          ),
          // AI 状态条(顶部居中):把「AI 正在干什么」说成一句人话,并给回跟随开关。
          Positioned(
            top: RevericSpacing.lg,
            left: 0,
            right: 0,
            child: Center(
              // 只让这条 pill 跟着导演重建 —— 一拍里状态会变好几次,
              // 拖着整块画布重建不值当。
              child: ListenableBuilder(
                listenable: aiDirector,
                builder: (context, _) {
                  return CanvasAiStatusPill(
                    visible: aiDirector.statusVisible,
                    kind: aiDirector.statusKind,
                    multi: aiDirector.isMultiKind,
                    following: aiDirector.isFollowing,
                    onToggleFollow: () =>
                        aiDirector.setFollowing(!aiDirector.isFollowing),
                  );
                },
              ),
            ),
          ),
          // 左下角工具簇：适配视图 / 画布操作 / 缩放菜单，与制作画布同一排布。
          Positioned(
            left: RevericSpacing.x2l,
            bottom: RevericSpacing.x2l,
            child: _CanvasToolCluster(
              controller: controller,
              onAddReference: onAddReference,
              onAddSticky: onAddSticky,
              layoutControl: editSession != null && onLayout != null
                  ? CanvasLayoutMenu(
                      canvasId: canvasId,
                      databasePath: databasePath,
                      session: editSession!,
                      onSelected: onLayout!,
                    )
                  : CanvasFloatingButton(
                      icon: RevericIcons.account_tree,
                      tooltip: context.t(LocaleKeys.canvasAutoLayoutTooltip),
                      onTap: onAutoLayout,
                    ),
              exportControl: exportControl,
              onCleanDead: onCleanDead,
              deadCount: invalidNodeIds.length,
            ),
          ),
        ],
      ),
    );
  }
}

/// 左下角工具簇：适配视图｜引用 / 便签 / 整理布局 / 导出｜清理失效｜缩放菜单。
///
/// 和制作画布的左下工具簇同一套横排胶囊；缩放百分比点开向上弹出缩放菜单。
class _CanvasToolCluster extends StatelessWidget {
  const _CanvasToolCluster({
    required this.controller,
    this.onAddReference,
    this.onAddSticky,
    required this.layoutControl,
    this.exportControl,
    this.onCleanDead,
    required this.deadCount,
  });

  final CanvasFlowController controller;
  final VoidCallback? onAddReference;
  final VoidCallback? onAddSticky;
  final Widget layoutControl;
  final Widget? exportControl;
  final VoidCallback? onCleanDead;
  final int deadCount;

  static const _zoomStep = 1.25;

  @override
  Widget build(BuildContext context) {
    return CanvasFloatingCluster(
      axis: Axis.horizontal,
      children: [
        CanvasFloatingButton(
          icon: RevericIcons.fit_screen,
          tooltip: context.t(LocaleKeys.canvasFitToView),
          onTap: controller.fitToView,
        ),
        CanvasFloatingButton(
          icon: RevericIcons.add,
          tooltip: context.t(LocaleKeys.canvasAddReference),
          onTap: onAddReference,
          divider: true,
        ),
        CanvasFloatingButton(
          icon: RevericIcons.edit_note_outlined,
          tooltip: context.t(LocaleKeys.canvasAddSticky),
          onTap: onAddSticky,
        ),
        layoutControl,
        ?exportControl,
        if (deadCount > 0)
          CanvasFloatingButton(
            icon: RevericIcons.delete_outline,
            tooltip: context.t(LocaleKeys.canvasCleanDead),
            onTap: onCleanDead,
            danger: true,
            divider: true,
          ),
        CanvasZoomControl(
          zoom: () => controller.viewportObservable.value.zoom,
          onZoomOut: () =>
              controller.zoomBy(controller.viewport.zoom * (1 / _zoomStep - 1)),
          onZoomIn: () =>
              controller.zoomBy(controller.viewport.zoom * (_zoomStep - 1)),
          onFit: controller.fitToView,
          // zoomBy 以视口中心为锚，zoomTo 会绕左上角缩放。
          onZoomTo: (target) =>
              controller.zoomBy(target - controller.viewport.zoom),
        ),
      ],
    );
  }
}

/// 内容签名比对：只有渲染结果会变时才重新 load，
/// 避免 stream 重发相同快照导致 flow controller 频繁 reset。
///
/// 签名必须包含**所有影响渲染的字段**，不能只比 id 集合：节点卡片与连线读的是
/// loadGraph 时的快照，坐标/正文/边类型只改字段不改 id —— 只比 id 的话自动重排、
/// AI 改坐标、面板改边 label 都会写库成功而画布纹丝不动。
///
/// 提到顶层是为了能被单测直接覆盖：整块 board 的 widget 测试会被 flow 库的
/// 动画 timer 卡住，而这段判断正是「改了却不刷新」这类 bug 的唯一闸门。
bool sameCanvasContentSignature(
  ({List<CanvasNode> nodes, List<CanvasEdge> edges})? previous,
  ({List<CanvasNode> nodes, List<CanvasEdge> edges}) current,
) {
  if (previous == null) return false;
  if (previous.nodes.length != current.nodes.length) return false;
  if (previous.edges.length != current.edges.length) return false;

  final prevNodes = {
    for (final n in previous.nodes) n.id: _canvasNodeSignature(n),
  };
  for (final node in current.nodes) {
    if (prevNodes[node.id] != _canvasNodeSignature(node)) return false;
  }
  final prevEdges = {
    for (final e in previous.edges) e.id: _canvasEdgeSignature(e),
  };
  for (final edge in current.edges) {
    if (prevEdges[edge.id] != _canvasEdgeSignature(edge)) return false;
  }
  return true;
}

/// 新节点入场动效的 id 留存窗口。略长于入场时长(260ms),覆盖挂载延迟;
/// 窗口外滚出视口再回来的节点不重复播入场。
const Duration _recentEntryWindow = Duration(milliseconds: 500);

/// 内容差集:两次快照之间的增/删/改。
///
/// 只含增删时 board 走增量挂载(新节点入场、新边生长);一旦带「改」
/// (坐标/正文/边类型等字段变化)就回退整图重载 —— flow 节点的 data 不可变,
/// 原地改内容得重建节点并级联重建连线,代价与风险都高于重载整图。
class CanvasContentDiff {
  const CanvasContentDiff({
    required this.addedNodes,
    required this.removedNodeIds,
    required this.addedEdges,
    required this.removedEdgeIds,
    required this.hasModifications,
  });

  /// 当前快照里新出现的节点。
  final List<CanvasNode> addedNodes;

  /// 当前快照里消失的节点 id。
  final Set<String> removedNodeIds;

  /// 当前快照里新出现的边。
  final List<CanvasEdge> addedEdges;

  /// 当前快照里消失的边 id。
  final Set<String> removedEdgeIds;

  /// 是否存在「同 id 但渲染字段变了」的节点或边。
  final bool hasModifications;
}

/// 比较两次内容快照,产出增/删/改差集。
///
/// 字段比较口径与 [sameCanvasContentSignature] 完全一致(同一套签名函数),
/// 提到顶层是为了能被单测直接覆盖。
CanvasContentDiff diffCanvasContent(
  ({List<CanvasNode> nodes, List<CanvasEdge> edges}) previous,
  ({List<CanvasNode> nodes, List<CanvasEdge> edges}) current,
) {
  final prevNodes = {for (final node in previous.nodes) node.id: node};
  final currentNodeIds = {for (final node in current.nodes) node.id};
  final addedNodes = [
    for (final node in current.nodes)
      if (!prevNodes.containsKey(node.id)) node,
  ];
  final removedNodeIds = {
    for (final node in previous.nodes)
      if (!currentNodeIds.contains(node.id)) node.id,
  };

  final prevEdges = {for (final edge in previous.edges) edge.id: edge};
  final currentEdgeIds = {for (final edge in current.edges) edge.id};
  final addedEdges = [
    for (final edge in current.edges)
      if (!prevEdges.containsKey(edge.id)) edge,
  ];
  final removedEdgeIds = {
    for (final edge in previous.edges)
      if (!currentEdgeIds.contains(edge.id)) edge.id,
  };

  var hasModifications = false;
  for (final node in current.nodes) {
    final prev = prevNodes[node.id];
    if (prev != null &&
        _canvasNodeSignature(prev) != _canvasNodeSignature(node)) {
      hasModifications = true;
      break;
    }
  }
  if (!hasModifications) {
    for (final edge in current.edges) {
      final prev = prevEdges[edge.id];
      if (prev != null &&
          _canvasEdgeSignature(prev) != _canvasEdgeSignature(edge)) {
        hasModifications = true;
        break;
      }
    }
  }

  return CanvasContentDiff(
    addedNodes: addedNodes,
    removedNodeIds: removedNodeIds,
    addedEdges: addedEdges,
    removedEdgeIds: removedEdgeIds,
    hasModifications: hasModifications,
  );
}

/// 节点渲染签名。style 只取纸色 key —— 便签底色由它决定。
String _canvasNodeSignature(CanvasNode node) {
  return [
    node.type,
    node.refType ?? '',
    node.refId ?? '',
    node.title,
    node.content,
    node.x,
    node.y,
    node.width ?? '',
    node.height ?? '',
    canvasNodeColorValueOf(node.style) ?? '',
  ].join('|');
}

String _canvasEdgeSignature(CanvasEdge edge) {
  return [
    edge.sourceNodeId,
    edge.targetNodeId,
    edge.type,
    edge.label ?? '',
  ].join('|');
}
