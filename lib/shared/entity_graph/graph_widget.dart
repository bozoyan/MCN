// 职责: 实体关系图自定义可视化组件 — 力导向布局、圆形头像节点、带标签的边、画布图层导出捕获。
// 关联文件:
//   lib/shared/entity_graph/layout.dart
//   lib/shared/entity_graph/edge_painter.dart
//   lib/shared/entity_graph/png_export.dart
//   lib/shared/entity_graph/providers.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import '../widgets/character_avatar.dart';
import 'colors.dart';
import 'constants.dart';
import 'data.dart';
import 'edge_painter.dart';
import 'layout.dart';
import 'models.dart';
import 'png_export.dart';
import 'providers.dart';

class EntityGraphWidget extends HookConsumerWidget {
  const EntityGraphWidget({
    super.key,
    required this.databasePath,
    required this.nodes,
    required this.edges,
    this.selectedNodeKey,
    this.defaultCenterNodeKey,
    this.onNodeTap,
    this.onClearSelection,
    this.showLabels = true,
    this.showDirection = true,
    this.layoutGeneration = 0,
    this.exportController,
  });

  final String databasePath;
  final List<EntityNodeData> nodes;
  final List<EntityEdgeData> edges;
  final String? selectedNodeKey;
  final String? defaultCenterNodeKey;
  final ValueChanged<String>? onNodeTap;
  final VoidCallback? onClearSelection;
  final bool showLabels;
  final bool showDirection;
  final int layoutGeneration;

  /// 由外部面板持有；挂载后可把整块画布捕获成图片用于 PNG 导出。
  final EntityGraphExportController? exportController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hoveredNodeKey = useState<String?>(null);
    final debouncedHoveredNodeKey = useDebounced(
      hoveredNodeKey.value,
      const Duration(milliseconds: 220),
    );
    // 导出期间抑制聚焦淡化与 hover 卡片：静态图里的半透明节点看起来像渲染坏了。
    final isExporting = useState(false);
    final exportBoundaryKey = useMemoized(() => GlobalKey(), const []);
    final exportGeometry = useRef<({Rect contentRect, Size canvasSize})?>(null);

    useEffect(() {
      final controller = exportController;
      if (controller == null) {
        return null;
      }
      Future<EntityGraphCapture> capture() async {
        final geometry = exportGeometry.value;
        if (geometry == null) {
          throw StateError('关系图尚未完成布局，无法导出');
        }
        isExporting.value = true;
        try {
          // endOfFrame 在导出态重建并完成绘制后才 complete，图层此时已是最终画面。
          await WidgetsBinding.instance.endOfFrame;
          final boundary =
              exportBoundaryKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
          if (boundary == null) {
            throw StateError('关系图画布未挂载，无法导出');
          }
          final pixelRatio = entityGraphExportPixelRatio(geometry.canvasSize);
          final image = await boundary.toImage(pixelRatio: pixelRatio);
          return EntityGraphCapture(
            image: image,
            contentRect: geometry.contentRect,
            pixelRatio: pixelRatio,
          );
        } finally {
          isExporting.value = false;
        }
      }

      controller.attach(capture);
      return () => controller.detach(capture);
    }, [exportController]);

    // centerNodeKey 用于相机居中与视觉焦点（选中节点 > 默认中心）；
    // 布局根固定为 defaultCenterNodeKey，与聚焦解耦，
    // 保证聚焦/取消聚焦时同一节点位置不变（确定性布局规则）。
    final centerNodeKey = selectedNodeKey ?? defaultCenterNodeKey;
    final layoutFingerprint = entityGraphLayoutFingerprint(
      nodes: nodes,
      edges: edges,
      centerNodeKey: defaultCenterNodeKey,
      layoutGeneration: layoutGeneration,
    );

    final positions = useMemoized(
      () => computeEntityGraphLayout(
        nodes: nodes,
        edges: edges,
        centerNodeKey: defaultCenterNodeKey,
        layoutSeed: 42 + layoutGeneration,
      ),
      [layoutFingerprint],
    );

    final nodeByKey = useMemoized(() {
      return {for (final node in nodes) node.key: node};
    }, [nodes]);
    final effectiveHoveredNodeKey =
        hoveredNodeKey.value == debouncedHoveredNodeKey
        ? debouncedHoveredNodeKey
        : null;
    final highlightedNodeKey = selectedNodeKey ?? effectiveHoveredNodeKey;
    final hoveredNode = effectiveHoveredNodeKey == null
        ? null
        : nodeByKey[effectiveHoveredNodeKey];
    final hoveredNodeDetail = hoveredNode == null
        ? null
        : ref.watch(
            entityGraphNodeDetailProvider(
              databasePath: databasePath,
              entityType: hoveredNode.entityType,
              entityId: hoveredNode.entityId,
            ),
          );

    final transformController = useTransformationController();
    final autoFitCenterNodeKey = defaultCenterNodeKey;

    useEffect(() {
      if (nodes.isEmpty) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _zoomToFit(
          transformController,
          positions,
          context,
          autoFitCenterNodeKey,
          showLabels,
        );
      });
      return null;
    }, [layoutFingerprint, autoFitCenterNodeKey, showLabels]);

    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final bounds = computeEntityGraphContentBounds(
      positions,
      includeLabels: showLabels,
    );
    final offset = _canvasOffsetForBounds(bounds);
    final canvasSize = Size(
      bounds.width + kEntityGraphNodeSpacing * 2,
      bounds.height + kEntityGraphNodeSpacing * 2,
    );
    exportGeometry.value = (
      contentRect: bounds.shift(offset),
      canvasSize: canvasSize,
    );
    final hoverCardOffset = hoveredNode == null
        ? null
        : _hoverCardOffset(positions[hoveredNode.key], offset, canvasSize);

    // 焦点高亮：有焦点节点时，非相连节点淡化（导出时不淡化）。
    final connectedKeys = highlightedNodeKey == null || isExporting.value
        ? null
        : _connectedNodeKeys(edges, highlightedNodeKey);
    // 中心节点统计（直接/间接关系数）。
    final centerStats = centerNodeKey == null
        ? null
        : entityGraphCenterStats(edges, centerNodeKey);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          key: const ValueKey('entity_graph_viewport'),
          behavior: HitTestBehavior.opaque,
          onTap: selectedNodeKey != null ? onClearSelection : null,
          child: Stack(
            children: [
              // 点阵背景（固定于视口，不随缩放平移）。
              Positioned.fill(
                child: CustomPaint(
                  painter: _DotGridPainter(
                    color: colors.border,
                    spacing: kEntityGraphDotGridSpacing,
                  ),
                ),
              ),
              // 图谱。
              Positioned.fill(
                child: InteractiveViewer.builder(
                  transformationController: transformController,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: kEntityGraphZoomMin,
                  maxScale: kEntityGraphZoomMax,
                  builder: (context, viewport) {
                    return RepaintBoundary(
                      key: exportBoundaryKey,
                      child: SizedBox(
                        width: canvasSize.width,
                        height: canvasSize.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: EntityGraphEdgePainter(
                                  edges: edges,
                                  positions: positions,
                                  offset: offset,
                                  showLabels: showLabels,
                                  showDirection: showDirection,
                                  highlightedNodeKey: highlightedNodeKey,
                                  labelBgColor: colors.surface,
                                  includeNodeLabels: showLabels,
                                ),
                              ),
                            ),
                            for (final node in nodes)
                              if (positions.containsKey(node.key))
                                _positionedNode(
                                  node: node,
                                  position: positions[node.key]!,
                                  offset: offset,
                                  isSelected: node.key == selectedNodeKey,
                                  isCenter: node.key == centerNodeKey,
                                  dimmed:
                                      connectedKeys != null &&
                                      !connectedKeys.contains(node.key),
                                  centerStats: node.key == centerNodeKey
                                      ? centerStats
                                      : null,
                                  colors: colors,
                                  typo: typo,
                                  hoveredNodeKey: hoveredNodeKey,
                                  showLabel: showLabels,
                                ),
                            if (!isExporting.value &&
                                hoveredNode != null &&
                                hoveredNodeDetail != null &&
                                hoverCardOffset != null)
                              Positioned(
                                left: hoverCardOffset.dx,
                                top: hoverCardOffset.dy,
                                child: _EntityNodeHoverCard(
                                  node: hoveredNode,
                                  detail: hoveredNodeDetail,
                                  colors: colors,
                                  typo: typo,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 重置视图。
              Positioned(
                top: RevericSpacing.x2l,
                right: RevericSpacing.x2l,
                child: _CanvasOverlayButton(
                  icon: RevericIcons.arrow_clockwise,
                  tooltip: context.t(LocaleKeys.entityGraphResetView),
                  colors: colors,
                  typo: typo,
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _zoomToFit(
                        transformController,
                        positions,
                        context,
                        centerNodeKey,
                        showLabels,
                      );
                    });
                  },
                ),
              ),
              // 缩放控件。
              Positioned(
                right: RevericSpacing.x2l,
                bottom: RevericSpacing.x2l,
                child: _ZoomControls(
                  controller: transformController,
                  viewport: viewport,
                  colors: colors,
                  typo: typo,
                  onZoom: (factor) =>
                      _zoomByFactor(transformController, viewport, factor),
                  onFit: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _zoomToFit(
                        transformController,
                        positions,
                        context,
                        centerNodeKey,
                        showLabels,
                      );
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Set<String> _connectedNodeKeys(List<EntityEdgeData> edges, String focusKey) {
    final keys = <String>{focusKey};
    for (final edge in edges) {
      if (edge.sourceKey == focusKey) {
        keys.add(edge.targetKey);
      } else if (edge.targetKey == focusKey) {
        keys.add(edge.sourceKey);
      }
    }
    return keys;
  }

  Widget _positionedNode({
    required EntityNodeData node,
    required Offset position,
    required Offset offset,
    required bool isSelected,
    required bool isCenter,
    required bool dimmed,
    required ({int direct, int indirect})? centerStats,
    required RevericColors colors,
    required RevericTypography typo,
    required ValueNotifier<String?> hoveredNodeKey,
    required bool showLabel,
  }) {
    final widgetWidth = isCenter
        ? kEntityGraphCenterNodeWidgetWidth
        : kEntityGraphNodeWidgetWidth;
    final totalSize = isCenter
        ? kEntityGraphCenterNodeTotalSize
        : kEntityGraphNodeTotalSize;
    return Positioned(
      left: position.dx + offset.dx - widgetWidth / 2,
      top: position.dy + offset.dy - totalSize / 2,
      child: Opacity(
        opacity: dimmed ? 0.2 : 1.0,
        child: _NodeWidget(
          node: node,
          isSelected: isSelected,
          isCenter: isCenter,
          centerStats: centerStats,
          colors: colors,
          typo: typo,
          onTap: () => onNodeTap?.call(node.key),
          onHoverStart: () {
            hoveredNodeKey.value = node.key;
          },
          onHoverEnd: () {
            if (hoveredNodeKey.value == node.key) {
              hoveredNodeKey.value = null;
            }
          },
          showLabel: showLabel,
        ),
      ),
    );
  }

  void _zoomByFactor(
    TransformationController controller,
    Size viewport,
    double factor,
  ) {
    final m = controller.value;
    final scale = m.storage[0];
    final newScale = (scale * factor).clamp(
      kEntityGraphZoomMin,
      kEntityGraphZoomMax,
    );
    if ((newScale - scale).abs() < 0.001) {
      return;
    }
    final ratio = newScale / scale;
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final tx = m.storage[12];
    final ty = m.storage[13];
    final newTx = cx - (cx - tx) * ratio;
    final newTy = cy - (cy - ty) * ratio;
    controller.value = Matrix4(
      newScale,
      0,
      0,
      0,
      0,
      newScale,
      0,
      0,
      0,
      0,
      1,
      0,
      newTx,
      newTy,
      0,
      1,
    );
  }

  void _zoomToFit(
    TransformationController controller,
    Map<String, Offset> positions,
    BuildContext context,
    String? centerNodeKey,
    bool includeLabels,
  ) {
    if (positions.isEmpty) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    final vp = renderBox.size;
    final bounds = computeEntityGraphContentBounds(
      positions,
      includeLabels: includeLabels,
    );
    final canvasOffset = _canvasOffsetForBounds(bounds);
    final contentBounds = bounds
        .shift(canvasOffset)
        .inflate(kEntityGraphNodeSpacing * 0.35);

    final scaleX = vp.width / contentBounds.width;
    final scaleY = vp.height / contentBounds.height;
    final scale = min(scaleX, scaleY).clamp(0.35, 1.6);

    final centerNodePos = centerNodeKey == null
        ? null
        : positions[centerNodeKey];

    double tx;
    double ty;
    if (centerNodePos != null) {
      final nodeCanvasPos = centerNodePos + canvasOffset;
      tx = vp.width / 2 - nodeCanvasPos.dx * scale;
      ty = vp.height / 2 - nodeCanvasPos.dy * scale;
    } else {
      final scaledWidth = contentBounds.width * scale;
      final scaledHeight = contentBounds.height * scale;
      tx = (vp.width - scaledWidth) / 2 - contentBounds.left * scale;
      ty = (vp.height - scaledHeight) / 2 - contentBounds.top * scale;
    }

    controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  Offset _canvasOffsetForBounds(Rect bounds) {
    return Offset(
      kEntityGraphNodeSpacing - bounds.left,
      kEntityGraphNodeSpacing - bounds.top,
    );
  }

  Offset? _hoverCardOffset(
    Offset? nodePosition,
    Offset canvasOffset,
    Size canvasSize,
  ) {
    if (nodePosition == null) {
      return null;
    }

    final center = nodePosition + canvasOffset;
    final right =
        center.dx + kEntityGraphNodeTotalSize / 2 + RevericSpacing.lg;
    final left =
        right + kEntityGraphHoverCardWidth <=
            canvasSize.width - RevericSpacing.x2l
        ? right
        : center.dx -
              kEntityGraphNodeTotalSize / 2 -
              RevericSpacing.lg -
              kEntityGraphHoverCardWidth;
    final top = (center.dy - kEntityGraphHoverCardEstimatedHeight / 2)
        .clamp(
          RevericSpacing.x2l,
          max(
            RevericSpacing.x2l,
            canvasSize.height - kEntityGraphHoverCardEstimatedHeight,
          ),
        )
        .toDouble();

    return Offset(max(RevericSpacing.x2l, left), top);
  }
}

class _NodeWidget extends StatelessWidget {
  const _NodeWidget({
    required this.node,
    required this.isSelected,
    required this.colors,
    required this.typo,
    required this.onTap,
    required this.onHoverStart,
    required this.onHoverEnd,
    this.isCenter = false,
    this.centerStats,
    this.showLabel = true,
  });

  final EntityNodeData node;
  final bool isSelected;
  final bool isCenter;
  final ({int direct, int indirect})? centerStats;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;
  final VoidCallback onHoverStart;
  final VoidCallback onHoverEnd;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final ringColor = entityGraphRingColor(
      node.entityType,
      colors,
      typeKey: node.typeKey,
    );
    final baseRingWidth = isCenter
        ? kEntityGraphCenterNodeRingWidth
        : kEntityGraphNodeRingWidth;
    final ringWidth = isSelected ? baseRingWidth + 1.5 : baseRingWidth;
    final totalSize = isCenter
        ? kEntityGraphCenterNodeTotalSize
        : kEntityGraphNodeTotalSize;
    final avatarSize = isCenter
        ? kEntityGraphCenterNodeAvatarSize - 4
        : kEntityGraphNodeAvatarSize - 4;
    final widgetWidth = isCenter
        ? kEntityGraphCenterNodeWidgetWidth
        : kEntityGraphNodeWidgetWidth;

    List<BoxShadow>? boxShadow;
    if (isCenter) {
      boxShadow = [
        BoxShadow(
          color: colors.selected.withValues(alpha: 0.7),
          blurRadius: 0,
          spreadRadius: kEntityGraphCenterNodeHaloSpread,
        ),
        BoxShadow(
          color: ringColor.withValues(alpha: 0.18),
          blurRadius: 12,
          spreadRadius: 3,
        ),
      ];
    } else if (isSelected) {
      boxShadow = [
        BoxShadow(
          color: ringColor.withValues(alpha: 0.3),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ];
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverStart(),
      onExit: (_) => onHoverEnd(),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: widgetWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: totalSize,
                height: totalSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: ringWidth),
                  color: colors.surfaceContainerHigh,
                  boxShadow: boxShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: node.entityType == 'character'
                      ? CharacterAvatar(
                          avatarAssetId: node.avatarAssetId,
                          fallbackName: node.name,
                          fallbackMaxChars: kEntityGraphAvatarFallbackMaxChars,
                          size: avatarSize,
                          backgroundColor: ringColor.withValues(alpha: 0.15),
                          textColor: ringColor,
                        )
                      : _EntityIconAvatar(
                          entityType: node.entityType,
                          color: ringColor,
                          size: avatarSize,
                        ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      (isCenter
                              ? typo.uiSmallSemibold.copyWith(fontSize: 15)
                              : typo.uiSmallSemibold)
                          .copyWith(color: colors.textPrimary),
                ),
                if (node.typeName != null)
                  Text(
                    node.typeName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                if (isCenter && centerStats != null) ...[
                  const SizedBox(height: RevericSpacing.xxs),
                  _CenterStatRow(
                    stats: centerStats!,
                    colors: colors,
                    typo: typo,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterStatRow extends StatelessWidget {
  const _CenterStatRow({
    required this.stats,
    required this.colors,
    required this.typo,
  });

  final ({int direct, int indirect}) stats;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kEntityGraphCenterNodeWidgetWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatPill(
              label: context.t(LocaleKeys.entityGraphStatDirect),
              value: stats.direct,
              colors: colors,
              typo: typo,
            ),
            const SizedBox(width: RevericSpacing.xxs),
            _StatPill(
              label: context.t(LocaleKeys.entityGraphStatIndirect),
              value: stats.indirect,
              colors: colors,
              typo: typo,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.colors,
    required this.typo,
  });

  final String label;
  final int value;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        '$label $value',
        style: typo.uiTiny.copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _CanvasOverlayButton extends StatelessWidget {
  const _CanvasOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          child: Container(
            width: kEntityGraphZoomButtonSize,
            height: kEntityGraphZoomButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              border: Border.all(color: colors.border),
            ),
            child: RevericIcon(icon, size: 14, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.controller,
    required this.viewport,
    required this.colors,
    required this.typo,
    required this.onZoom,
    required this.onFit,
  });

  final TransformationController controller;
  final Size viewport;
  final RevericColors colors;
  final RevericTypography typo;
  final ValueChanged<double> onZoom;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: RevericIcons.add,
            tooltip: context.t(LocaleKeys.entityGraphZoomIn),
            colors: colors,
            onTap: () => onZoom(kEntityGraphZoomStep),
          ),
          _ZoomButton(
            icon: RevericIcons.close,
            iconRotation: pi / 4,
            tooltip: context.t(LocaleKeys.entityGraphZoomOut),
            colors: colors,
            onTap: () => onZoom(1 / kEntityGraphZoomStep),
          ),
          _ZoomButton(
            icon: RevericIcons.open_in_full_rounded,
            tooltip: context.t(LocaleKeys.entityGraphZoomFit),
            colors: colors,
            onTap: onFit,
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final scale = controller.value.storage[0];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${(scale * 100).round()}%',
                  style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
    this.iconRotation = 0,
  });

  final String icon;
  final String tooltip;
  final RevericColors colors;
  final VoidCallback onTap;
  final double iconRotation;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: SizedBox(
          width: kEntityGraphZoomButtonSize,
          height: kEntityGraphZoomButtonSize,
          child: Center(
            child: Transform.rotate(
              angle: iconRotation,
              child: RevericIcon(icon, size: 15, color: colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color, required this.spacing});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = kEntityGraphDotGridDotRadius;
    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.spacing != spacing;
  }
}

class _EntityNodeHoverCard extends StatelessWidget {
  const _EntityNodeHoverCard({
    required this.node,
    required this.detail,
    required this.colors,
    required this.typo,
  });

  final EntityNodeData node;
  final AsyncValue<EntityGraphNodeDetail?> detail;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    final ringColor = entityGraphRingColor(
      node.entityType,
      colors,
      typeKey: node.typeKey,
    );
    return Material(
      color: Colors.transparent,
      child: Container(
        width: kEntityGraphHoverCardWidth,
        padding: const EdgeInsets.all(RevericSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.borderInput),
        ),
        child: detail.when(
          loading: () => _EntityNodeHoverCardLoading(
            node: node,
            ringColor: ringColor,
            colors: colors,
            typo: typo,
          ),
          error: (_, _) => _EntityNodeHoverCardContent(
            node: node,
            title: node.name,
            typeName: node.typeName,
            description: context.t(LocaleKeys.commonNoDescription),
            ringColor: ringColor,
            colors: colors,
            typo: typo,
          ),
          data: (detail) => _EntityNodeHoverCardContent(
            node: node,
            title: _emptyToFallback(detail?.title, node.name),
            typeName: node.typeName,
            description:
                detail?.description ??
                context.t(LocaleKeys.commonNoDescription),
            metaLabel: _localizedMetaLabel(context, detail?.metaLabel),
            metaValue: _localizedMetaValue(context, detail?.metaValue),
            ringColor: ringColor,
            colors: colors,
            typo: typo,
          ),
        ),
      ),
    );
  }
}

class _EntityNodeHoverCardLoading extends StatelessWidget {
  const _EntityNodeHoverCardLoading({
    required this.node,
    required this.ringColor,
    required this.colors,
    required this.typo,
  });

  final EntityNodeData node;
  final Color ringColor;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EntityNodeHoverAvatar(node: node, ringColor: ringColor),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      ],
    );
  }
}

class _EntityNodeHoverCardContent extends StatelessWidget {
  const _EntityNodeHoverCardContent({
    required this.node,
    required this.title,
    required this.typeName,
    required this.description,
    required this.ringColor,
    required this.colors,
    required this.typo,
    this.metaLabel,
    this.metaValue,
  });

  final EntityNodeData node;
  final String title;
  final String? typeName;
  final String description;
  final String? metaLabel;
  final String? metaValue;
  final Color ringColor;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _EntityNodeHoverAvatar(node: node, ringColor: ringColor),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (typeName != null) ...[
                    Text(
                      typeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (metaLabel != null && metaValue != null) ...[
          const SizedBox(height: RevericSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Text(
              '$metaLabel: $metaValue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiTiny.copyWith(color: colors.textMuted),
            ),
          ),
        ],
        const SizedBox(height: RevericSpacing.sm),
        Text(
          _compactPreview(description),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: typo.uiSmall.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _EntityNodeHoverAvatar extends StatelessWidget {
  const _EntityNodeHoverAvatar({required this.node, required this.ringColor});

  final EntityNodeData node;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: node.entityType == 'character'
          ? CharacterAvatar(
              avatarAssetId: node.avatarAssetId,
              fallbackName: node.name,
              fallbackMaxChars: kEntityGraphAvatarFallbackMaxChars,
              size: 34,
              backgroundColor: ringColor.withValues(alpha: 0.15),
              textColor: ringColor,
            )
          : _EntityIconAvatar(
              entityType: node.entityType,
              color: ringColor,
              size: 34,
            ),
    );
  }
}

String _emptyToFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _compactPreview(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String? _localizedMetaLabel(BuildContext context, String? value) {
  switch (value) {
    case 'role':
      return context.t(LocaleKeys.commonRole);
    case 'status':
      return context.t(LocaleKeys.commonStatus);
    default:
      return null;
  }
}

String? _localizedMetaValue(BuildContext context, String? value) {
  switch (value) {
    case 'protagonist':
      return context.t(LocaleKeys.characterRoleProtagonist);
    case 'antagonist':
      return context.t(LocaleKeys.characterRoleAntagonist);
    case 'supporting':
      return context.t(LocaleKeys.characterRoleSupporting);
    case 'minor':
      return context.t(LocaleKeys.characterRoleMinor);
    case null:
      return null;
    default:
      return value;
  }
}

class _EntityIconAvatar extends StatelessWidget {
  const _EntityIconAvatar({
    required this.entityType,
    required this.color,
    required this.size,
  });

  final String entityType;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Center(
        child: RevericIcon(
          entityGraphIcon(entityType),
          size: size * 0.45,
          color: color,
        ),
      ),
    );
  }
}
