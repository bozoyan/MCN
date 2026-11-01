// 职责: 画布 AI 焦点高亮浮层 — 给 AI 刚刚动过的节点各画一圈独立淡出的脉冲环
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/canvas_ai_director.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
// layer_provider / unbounded_widgets 未在库 barrel 导出，直接引 src(与 canvas_detail_layer.dart 同一先例)。
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/unbounded_widgets.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/plugins/layer_provider.dart';

import '../../../../shared/theme/theme.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../canvas_ai_director.dart';
import 'canvas_flow_adapter.dart';

/// AI 焦点高亮 plugin。
///
/// 为什么单独做一层而不是把「高亮」塞进节点数据：节点卡片走
/// `canvasContentToFlowGraph` 重建，高亮是 1 秒内就消失的瞬时状态，塞进内容签名
/// 会让 `loadGraph` 反复触发、画布跟着闪。这里在前景节点之上单独补一圈环。
///
/// 环画在画布坐标系里（随画布变换一起走），而不是 overlays 层的屏幕坐标：镜头
/// 动画只逐帧改 TransformationController，`viewportObservable` 要到动画结束才同步，
/// 按屏幕坐标画的环会在平移时钉在原地，节点从环里滑走。
///
/// 环的开合直接订阅 [CanvasAiDirector]，不经过 board 的 rebuild —— 一拍里
/// 节点是逐个揭示的，每揭示一个就要点亮一个环，走 board 会把整块画布跟着重建。
class CanvasAiFocusLayer extends flow.NodeFlowPlugin implements LayerProvider {
  CanvasAiFocusLayer();

  /// 焦点来源。由 board 每次 rebuild 同步。
  CanvasAiDirector? director;

  CanvasFlowController? _controller;

  @override
  String get id => 'canvas_ai_focus_layer';

  @override
  void attach(flow.NodeFlowController controller) {
    _controller = controller as CanvasFlowController;
  }

  @override
  void detach() {
    _controller = null;
  }

  @override
  void onEvent(flow.GraphEvent event) {
    // 纯展示层，不响应 graph 事件。
  }

  @override
  LayerPosition get layerPosition => NodeFlowLayer.foregroundNodes.after;

  @override
  Widget? buildLayer(BuildContext context) {
    final controller = _controller;
    final director = this.director;
    if (controller == null || director == null) {
      return null;
    }
    return UnboundedPositioned.fill(
      child: IgnorePointer(
        child: _CanvasAiFocusOverlay(
          controller: controller,
          director: director,
        ),
      ),
    );
  }
}

class _CanvasAiFocusOverlay extends StatefulWidget {
  const _CanvasAiFocusOverlay({
    required this.controller,
    required this.director,
  });

  final CanvasFlowController controller;
  final CanvasAiDirector director;

  @override
  State<_CanvasAiFocusOverlay> createState() => _CanvasAiFocusOverlayState();
}

/// 每个节点的环各自计时。
///
/// 旧实现是一个 AnimationController 带全部环，来一条新事件就 `forward(from: 0)`
/// 全体重播 —— 模型并发 6 个工具时，前 5 个环还没亮完就被顶掉，看上去是频闪。
/// 现在每个 nodeId 记自己的起始 [_starts]，互不打断；全部褪完就停 ticker，
/// 不留常驻重绘。
class _CanvasAiFocusOverlayState extends State<_CanvasAiFocusOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// ticker 本轮已经跑过的时间。ticker 停掉再启动会从 0 重新计，
  /// 所以重启前一定要把 [_starts] 清空。
  Duration _elapsed = Duration.zero;

  /// nodeId → 该环的起始时间（相对 [_elapsed]）。
  final Map<String, Duration> _starts = <String, Duration>{};

  /// nodeId → 已经点亮过的批次号，用来区分「新事件」与「重复通知」。
  final Map<String, int> _stamps = <String, int>{};

  @override
  void initState() {
    super.initState();
    widget.director.addListener(_syncFromDirector);
    _syncFromDirector();
  }

  @override
  void didUpdateWidget(covariant _CanvasAiFocusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.director != widget.director) {
      oldWidget.director.removeListener(_syncFromDirector);
      widget.director.addListener(_syncFromDirector);
      _syncFromDirector();
    }
  }

  @override
  void dispose() {
    widget.director.removeListener(_syncFromDirector);
    _ticker.dispose();
    super.dispose();
  }

  void _syncFromDirector() {
    if (!mounted) {
      return;
    }
    final stamps = widget.director.focusStamps;
    final incoming = <String>[
      for (final entry in stamps.entries)
        if (_stamps[entry.key] != entry.value) entry.key,
    ];
    _stamps.removeWhere((id, _) => !stamps.containsKey(id));
    if (incoming.isEmpty) {
      return;
    }
    // ticker 停着时 elapsed 会从 0 重新起算，残留的旧起点会立刻算成「已褪完」。
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _starts.clear();
    }
    for (final id in incoming) {
      _stamps[id] = stamps[id]!;
      _starts[id] = _elapsed;
    }
    if (!_ticker.isActive) {
      _ticker.start();
    }
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    _starts.removeWhere((_, start) => elapsed - start >= _ringDuration);
    if (_starts.isEmpty) {
      _ticker.stop();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_starts.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    return Observer(
      builder: (_) {
        final viewport = widget.controller.viewportObservable.value;
        final rings = <Widget>[];
        for (final entry in _starts.entries) {
          final progress =
              (_elapsed - entry.value).inMicroseconds /
              _ringDuration.inMicroseconds;
          if (progress < 0 || progress >= 1) {
            continue;
          }
          final node = widget.controller.getNode(entry.key);
          if (node == null || !node.isVisible) {
            continue;
          }
          // 先快速亮起再缓慢褪去：亮起要抓住视线，褪去不能打断阅读。
          final opacity = progress < 0.2
              ? progress / 0.2
              : 1 - (progress - 0.2) / 0.8;
          final position = node.position.value;
          final size = node.size.value;
          // 画布坐标系里的线宽会跟着缩放变细，除以 zoom 让屏幕上看到的粗细不变。
          // 缩放只在动画结束时同步，跟随期间缩放是锁定的，不影响观感。
          final scale = 1 / viewport.zoom;
          for (final (inset, width, alpha) in [
            // 外圈柔光：只画一圈宽而淡的边，不能用 BoxShadow —— 它会画满整块
            // 模糊矩形，叠在节点上面把卡片染灰。
            (_haloInset, _haloWidth, 0.22),
            (_ringInset, _ringWidth, 0.85),
          ]) {
            rings.add(
              UnboundedPositioned(
                left: position.dx - inset * scale,
                top: position.dy - inset * scale,
                width: size.width + inset * scale * 2,
                height: size.height + inset * scale * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      (RevericRadius.x2l + inset) * scale,
                    ),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: alpha * opacity),
                      width: width * scale,
                    ),
                  ),
                ),
              ),
            );
          }
        }
        if (rings.isEmpty) {
          return const SizedBox.shrink();
        }
        return UnboundedStack(clipBehavior: Clip.none, children: rings);
      },
    );
  }
}

/// 单个环从亮起到褪尽的时长。
const Duration _ringDuration = Duration(milliseconds: 900);

/// 环与节点边缘之间的呼吸量(屏幕像素)。
const double _ringInset = 6;
const double _ringWidth = 2;
const double _haloInset = 10;
const double _haloWidth = 6;
