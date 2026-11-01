// 职责: 剧本场次板 — 把当前集场次铺成一条 flow 画布时间轴，可平移缩放、禁拖拽
// 关联文件:
//   lib/desktop/features/screenplay/scenes.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/widgets/app_background.dart
//   lib/shared/theme/theme.dart
//   lib/third/flow/vyuh_node_flow.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import '../canvas/canvas_palette.dart';

/// 场次板上的一张卡。
///
/// [id] 同时作为 flow 节点 id 与连线端点，必须在一块板内唯一（用场次 id）。
class ScreenplayBoardCard {
  const ScreenplayBoardCard({required this.id, required this.child});

  final String id;
  final Widget child;
}

/// 场次板节点的左右连接点。
///
/// 场次是线性序列，连线永远是「上一场右边 → 下一场左边」，所以只要两个 port，
/// 不像画布那样四边都留。两个 port 都不可见（主题里 portTheme 全透明），也不
/// 承担拖拽连线 —— 场次板是 [flow.NodeFlowBehavior.inspect]，本就不建连线。
const _portLeft = 'scene-in';
const _portRight = 'scene-out';

/// 节点数据类型只需要携带场次 id，用它回查要渲染哪张卡。
typedef _BoardController = flow.NodeFlowController<String, String>;
typedef _BoardGraph = flow.NodeGraph<String, String>;

/// 第一张卡相对画布原点的让开量，沿用 mockup `.sp-board__inner` 的 56 / 44。
const _boardPadding = Offset(56, 44);

/// `.sp-board` —— 点阵画布上横排的场次卡，卡与卡之间用虚线连成时间轴。
///
/// 用真的 flow 画布而不是横向 `ScrollView`：底纹、平移、缩放、LOD 都由库提供，
/// 与「画布」分区同一套观感。行为取 [flow.NodeFlowBehavior.inspect] —— 可平移、
/// 缩放、选中，但不可拖拽：场次带场号、是有序序列，放开拖拽却不回写顺序只会
/// 让人以为改动没保存。
///
/// 节点位置每次按序号现算（`x = index * (卡宽 + 间距)`），不入库；场次板没有
/// 「自由摆位」这回事，存下来反而要处理增删场次后的空洞。
class ScreenplayBoard extends HookConsumerWidget {
  const ScreenplayBoard({super.key, required this.cards, this.focusCardId});

  final List<ScreenplayBoardCard> cards;

  /// 首次载入后居中的卡片；为空或找不到时停在第一张。
  final String? focusCardId;

  static const _cardSize = Size(
    RevericSizes.screenplaySceneCardWidth,
    RevericSizes.screenplaySceneCardHeight,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typography = RevericTheme.typographyOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    final controller = useMemoized(
      () => _BoardController(
        config: flow.NodeFlowConfig(
          minZoom: 0.2,
          maxZoom: 2.0,
          showAttribution: false,
          plugins: [
            // 默认 LOD 缩到最小会关掉节点内容，卡片直接消失（节点主题是全透明的，
            // 视觉全靠 nodeBuilder 自绘）。与画布同款：只放开 showNodeContent。
            ...flow.NodeFlowConfig.defaultPlugins().where(
              (plugin) => plugin is! flow.LodPlugin,
            ),
            flow.LodPlugin(
              minVisibility: flow.DetailVisibility.minimal.copyWith(
                showNodeContent: true,
              ),
            ),
          ],
        ),
      ),
      const [],
    );
    useEffect(() => controller.dispose, [controller]);

    final didLoad = useRef(false);

    // 只有场次集合或线色变了才重建图 —— 卡片内容变化走 nodeBuilder，不必重载。
    final signature = [
      colors.borderInput.toARGB32().toString(),
      for (final card in cards) card.id,
    ].join('|');

    useEffect(() {
      final isFirstLoad = !didLoad.value;
      // 重载会重置视口，所以首次之外都把当前视口原样带回去：改个梗概不该把
      // 用户已经推到第 12 场的画面弹回开头。
      final viewport = isFirstLoad
          ? const flow.GraphViewport()
          : controller.exportGraph().viewport;
      controller.loadGraph(
        _buildGraph(cards, colors: colors, viewport: viewport),
      );
      didLoad.value = true;

      // 开场镜头只在第一次载入时摆一次。
      //
      // 不能挂在编辑器的 onInit 上：那个事件在编辑器自身初始化完就触发，早于
      // 这里的 loadGraph，`getNode` 还是 null，镜头指令会静默落空。视口尺寸也
      // 要等挂载后才知道，所以推到下一帧。
      if (isFirstLoad) {
        final target = focusCardId;
        final index = cards.indexWhere((card) => card.id == target);
        // 只有回到「不在开场画面里」的场次才移镜头。第一场本就在左上角
        // (由 _boardPadding 让开边距)，居中反而会在左边空出半屏。
        if (index > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.getNode(target!) != null) {
              controller.centerOnNode(target);
            }
          });
        }
      }
      return null;
    }, [controller, signature]);

    final cardById = {for (final card in cards) card.id: card.child};

    return DecoratedBox(
      decoration: BoxDecoration(
        color: appChromeBackgroundColor(
          colors,
          appBackgroundActive,
          colors.canvas,
        ),
      ),
      child: flow.NodeFlowEditor<String, String>(
        controller: controller,
        theme: canvasFlowTheme(
          colors,
          typography,
          appBackgroundActive,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
        behavior: flow.NodeFlowBehavior.inspect,
        nodeBuilder: (context, node) =>
            cardById[node.id] ?? const SizedBox.shrink(),
      ),
    );
  }

  /// 按场次顺序摊成一条水平时间轴。
  ///
  /// 起点不放在画布原点：初始视口也在原点，第一张卡会正好顶着顶栏和左侧栏。
  /// 让开一个边距，默认画面里卡片才是「摆在板上」而不是「卡在角上」。
  static _BoardGraph _buildGraph(
    List<ScreenplayBoardCard> cards, {
    required RevericColors colors,
    required flow.GraphViewport viewport,
  }) {
    const step =
        RevericSizes.screenplaySceneCardWidth +
        RevericSizes.screenplaySceneCardGap;
    final nodes = [
      for (var index = 0; index < cards.length; index++)
        flow.Node<String>(
          id: cards[index].id,
          type: 'scene',
          position: Offset(_boardPadding.dx + index * step, _boardPadding.dy),
          size: _cardSize,
          data: cards[index].id,
          ports: _scenePorts(),
        ),
    ];
    final connections = [
      for (var index = 1; index < cards.length; index++)
        flow.Connection<String>(
          id: '${cards[index - 1].id}>${cards[index].id}',
          sourceNodeId: cards[index - 1].id,
          sourcePortId: _portRight,
          targetNodeId: cards[index].id,
          targetPortId: _portLeft,
          color: colors.borderInput,
          strokeWidth: 1,
          dashPattern: const [5, 4],
          // 时间轴的方向由场号表达，不必再画箭头。
          startPoint: const flow.ConnectionEndPoint(
            shape: flow.MarkerShapes.none,
            size: Size.zero,
          ),
          endPoint: const flow.ConnectionEndPoint(
            shape: flow.MarkerShapes.none,
            size: Size.zero,
          ),
        ),
    ];
    return _BoardGraph(
      nodes: nodes,
      connections: connections,
      viewport: viewport,
    );
  }

  /// 左右两个连接点。
  ///
  /// `offset` 必须显式给：vyuh_node_flow 对没有 NodeShape 的矩形节点，垂直于所在
  /// 边的那一轴完全取自 `Port.offset` 而不是节点尺寸，默认 `Offset.zero` 会把
  /// 连接点钉在节点角上，连线于是缩成卡片角上的一个小钩。
  static List<flow.Port> _scenePorts() {
    const centerY = Offset(0, RevericSizes.screenplaySceneCardHeight / 2);
    return [
      flow.Port(
        id: _portLeft,
        name: '',
        type: flow.PortType.both,
        position: flow.PortPosition.left,
        offset: centerY,
        isConnectable: false,
      ),
      flow.Port(
        id: _portRight,
        name: '',
        type: flow.PortType.both,
        position: flow.PortPosition.right,
        offset: centerY,
        isConnectable: false,
      ),
    ];
  }
}
