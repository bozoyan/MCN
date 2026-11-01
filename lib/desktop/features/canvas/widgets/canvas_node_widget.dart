// 职责: 展示画布引用与便签卡片，并实时投影场次标题、季集场号及失效状态。
// 关联文件:
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/scene_reference.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/canvas_scene_reference.dart';
import '../../../../shared/providers/canvas_providers.dart';
import '../../../../shared/theme/canvas_card_metrics.dart';
import '../../../../shared/theme/theme.dart';
import '../canvas_palette.dart';
import '../scene_reference.dart';
import 'canvas_flow_adapter.dart';

/// 画布节点卡片：按节点类型分派到引用型或便签型视觉。
///
/// 选中态只改描边与投影，**不在卡片内展开详情**——详情面板挂在 overlays 层
/// (见 `canvas_detail_layer.dart`)，因为节点内容被 flow 库约束在节点尺寸内，
/// 溢出部分收不到点击。
class CanvasNodeCard extends StatelessWidget {
  const CanvasNodeCard({
    super.key,
    required this.node,
    this.animateEntry = false,
    this.databasePath,
  });

  final CanvasFlowNode node;
  final String? databasePath;

  /// 首次出现时播一次入场动效。
  ///
  /// 由 board 在新增节点的入场窗口内开启；整图重载时不重复播放。
  final bool animateEntry;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final data = node.data;
        final isSelected = node.isSelected;
        final Widget card;
        if (data.node.type == canvasNodeTypeSticky) {
          card = CanvasStickyNodeCard(node: data.node, isSelected: isSelected);
        } else if (data.node.refType == canvasNodeRefTypeScreenplayScene &&
            databasePath != null) {
          card = Consumer(
            builder: (context, ref, _) {
              final reference = ref
                  .watch(canvasSceneReferencesProvider(databasePath!))
                  .value?[data.node.refId];
              return CanvasReferenceNodeCard(
                node: data.node,
                isInvalid: data.isInvalid,
                isSelected: isSelected,
                scene: reference,
              );
            },
          );
        } else {
          card = CanvasReferenceNodeCard(
            node: data.node,
            isInvalid: data.isInvalid,
            isSelected: isSelected,
          );
        }
        if (!animateEntry) {
          return card;
        }
        return _CanvasNodeEntryAnimation(child: card);
      },
    );
  }
}

/// 节点入场:淡入 + 轻微放大过冲。
///
/// 靠「首次构建即播放」而不是显式触发 —— flow 的 `NodeContainer` 在节点不可见时
/// 返回 `SizedBox.shrink()`,子树被卸载;转为可见时是一棵全新的 element 树,
/// 于是 [TweenAnimationBuilder] 天然只在露面那一刻播一次。
class _CanvasNodeEntryAnimation extends StatelessWidget {
  const _CanvasNodeEntryAnimation({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // easeOutBack 会冲过 1 再回落,过冲量压在 8% 以内:有弹性,不像果冻。
        final scale = 0.92 + 0.08 * value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: child,
    );
  }
}

/// 引用型节点卡片：类型图标 + 缓存标题 + 类型名。
///
/// 引用的资源被删除后节点不消失，改为失效态(虚线描边 + 标题删除线)：
/// 作者的构思结构比单个资源更重要，资源恢复后节点自动重新生效。
class CanvasReferenceNodeCard extends StatefulWidget {
  const CanvasReferenceNodeCard({
    super.key,
    required this.node,
    required this.isInvalid,
    required this.isSelected,
    this.scene,
  });

  final CanvasNode node;
  final bool isInvalid;
  final bool isSelected;

  /// 场次引用的投影；有值时标题与副标题取场次标题与季集场号。
  final CanvasSceneReference? scene;

  @override
  State<CanvasReferenceNodeCard> createState() =>
      _CanvasReferenceNodeCardState();
}

class _CanvasReferenceNodeCardState extends State<CanvasReferenceNodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final look = canvasReferenceCardLook(
      colors,
      typo,
      widget.node.refType,
      isInvalid: widget.isInvalid,
      colorValue: canvasNodeColorValueOf(widget.node.style),
    );
    final accent = look.accent;
    final (:title, :subtitle) = canvasReferenceCardText(
      context,
      title: widget.node.title,
      refType: widget.node.refType,
      isInvalid: widget.isInvalid,
      scene: widget.scene,
    );

    final borderColor = widget.isSelected
        ? accent
        : (_hovered
              ? Color.alphaBlend(accent.withValues(alpha: 0.55), look.border)
              : look.border);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CanvasReferenceCardMetrics.paddingX,
        ),
        decoration: BoxDecoration(
          color: look.fill,
          borderRadius: BorderRadius.circular(
            CanvasReferenceCardMetrics.radius,
          ),
          border: Border.all(
            color: widget.isInvalid ? look.border : borderColor,
            width: 1,
          ),
          boxShadow: [
            ...canvasNodeShadows(colors),
            if (widget.isSelected) canvasNodeSelectionRing(colors, accent),
          ],
        ),
        child: Row(
          children: [
            // 类型 chip：按资源类型着色，扫一眼即可分出人物/章节/伏笔。
            Container(
              width: CanvasReferenceCardMetrics.chipSize,
              height: CanvasReferenceCardMetrics.chipSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: look.chipFill,
                borderRadius: BorderRadius.circular(
                  CanvasReferenceCardMetrics.chipRadius,
                ),
                border: look.chipBorder == null
                    ? null
                    : Border.all(color: look.chipBorder!),
              ),
              child: RevericIcon(
                look.icon,
                size: CanvasReferenceCardMetrics.iconSize,
                color: look.iconColor,
              ),
            ),
            const SizedBox(width: CanvasReferenceCardMetrics.chipGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: title,
                    waitDuration: const Duration(milliseconds: 350),
                    child: Text(
                      title,
                      style: look.titleStyle,
                      maxLines: CanvasReferenceCardMetrics.titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Tooltip(
                    message: subtitle,
                    waitDuration: const Duration(milliseconds: 350),
                    child: Text(
                      subtitle,
                      style: look.subtitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 引用卡片的标题与副标题；画布卡片与导出预览共用。
({String title, String subtitle}) canvasReferenceCardText(
  BuildContext context, {
  required String title,
  required String? refType,
  required bool isInvalid,
  CanvasSceneReference? scene,
}) {
  final type = refType ?? canvasNodeRefTypeDocument;
  final shown = scene != null
      ? canvasSceneTitle(context, scene)
      : title.isEmpty
      ? context.t(LocaleKeys.canvasInvalidReference)
      : title;
  final subtitle = isInvalid
      ? '${canvasRefTypeLabel(context, type)} · ${context.t(LocaleKeys.canvasInvalidReference)}'
      : scene != null
      ? canvasSceneLocationLabel(context, scene)
      : canvasRefTypeLabel(context, type);
  return (title: shown, subtitle: subtitle);
}

/// 引用卡片常态（未选中、未悬停）的外观；画布卡片与导出预览共用。
typedef CanvasReferenceCardLook = ({
  Color fill,
  Color border,
  Color accent,
  Color chipFill,
  Color? chipBorder,
  String icon,
  Color iconColor,
  TextStyle titleStyle,
  TextStyle subtitleStyle,
});

CanvasReferenceCardLook canvasReferenceCardLook(
  RevericColors colors,
  RevericTypography typo,
  String? refType, {
  required bool isInvalid,
  String? colorValue,
}) {
  final type = refType ?? canvasNodeRefTypeDocument;
  // chip 始终按资源类型着色，用户设的颜色只染卡片本身，类型仍一眼可分。
  final typeAccent = isInvalid
      ? colors.textSubtle
      : canvasRefTypeAccent(colors, type);
  final hue = isInvalid ? null : canvasNodeHueColor(colors, colorValue);
  return (
    fill: isInvalid
        ? colors.surfaceDim
        : hue == null
        ? colors.surface
        : canvasNodePaperColor(colors, colorValue!),
    border: hue == null
        ? colors.borderInput
        : Color.alphaBlend(hue.withValues(alpha: 0.45), colors.borderInput),
    accent: hue ?? typeAccent,
    chipFill: isInvalid
        ? colors.surfaceDim
        : typeAccent.withValues(alpha: colors.isDark ? 0.20 : 0.13),
    chipBorder: isInvalid ? colors.borderInput : null,
    icon: isInvalid ? RevericIcons.warning_circle : canvasRefTypeIcon(type),
    iconColor: typeAccent,
    titleStyle: typo.uiSemibold.copyWith(
      color: isInvalid ? colors.textMuted : colors.textPrimary,
      decoration: isInvalid ? TextDecoration.lineThrough : null,
      decorationColor: colors.textSubtle,
    ),
    subtitleStyle: typo.uiTiny.copyWith(color: colors.textMuted),
  );
}

/// 便签卡片标签行与正文的展示文字（空值落到占位文案）；画布卡片与导出预览共用。
({String label, String body}) canvasStickyCardText(
  BuildContext context, {
  required String title,
  required String content,
}) {
  return (
    label: title.isEmpty ? context.t(LocaleKeys.canvasStickyLabel) : title,
    body: content.isEmpty
        ? context.t(LocaleKeys.canvasStickyPlaceholder)
        : content,
  );
}

/// 便签卡片常态（未选中）的外观；画布卡片与导出预览共用。
typedef CanvasStickyCardLook = ({
  Color paper,
  Color border,
  String icon,
  Color iconColor,
  TextStyle labelStyle,
  TextStyle bodyStyle,
});

CanvasStickyCardLook canvasStickyCardLook(
  RevericColors colors,
  RevericTypography typo,
  String? colorKey, {
  required bool isEmpty,
}) {
  final ink = canvasStickyInkColor(colors);
  return (
    paper: canvasStickyPaperColor(colors, colorKey),
    border: ink.withValues(alpha: colors.isDark ? 0.20 : 0.12),
    icon: RevericIcons.edit_note_outlined,
    iconColor: ink.withValues(alpha: 0.52),
    labelStyle: typo.uiTinySemibold.copyWith(
      color: ink.withValues(alpha: 0.60),
      letterSpacing: CanvasStickyCardMetrics.labelLetterSpacing,
    ),
    bodyStyle: typo.bodySmall.copyWith(
      color: ink.withValues(alpha: isEmpty ? 0.40 : 0.88),
      height: CanvasStickyCardMetrics.bodyHeight,
    ),
  );
}

/// 便签节点卡片：纸色底 + 小标签 + serif 正文。
///
/// 正文用 serif(与正文编辑器同族)而非 UI 字体：便签写的是小说内容的片段，
/// 视觉上应归属"稿纸"而非"界面"。
class CanvasStickyNodeCard extends StatelessWidget {
  const CanvasStickyNodeCard({
    super.key,
    required this.node,
    required this.isSelected,
  });

  final CanvasNode node;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final look = canvasStickyCardLook(
      colors,
      typo,
      canvasStickyColorKeyOf(node.style),
      isEmpty: node.content.isEmpty,
    );
    final (:label, :body) = canvasStickyCardText(
      context,
      title: node.title,
      content: node.content,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(
        CanvasStickyCardMetrics.paddingLeft,
        CanvasStickyCardMetrics.paddingTop,
        CanvasStickyCardMetrics.paddingRight,
        CanvasStickyCardMetrics.paddingBottom,
      ),
      decoration: BoxDecoration(
        color: look.paper,
        borderRadius: BorderRadius.circular(CanvasStickyCardMetrics.radius),
        border: Border.all(
          color: isSelected ? colors.accent : look.border,
          width: 1,
        ),
        boxShadow: [
          ...canvasNodeShadows(colors),
          if (isSelected) canvasNodeSelectionRing(colors, colors.accent),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                look.icon,
                size: CanvasStickyCardMetrics.iconSize,
                color: look.iconColor,
              ),
              const SizedBox(width: CanvasStickyCardMetrics.iconGap),
              Expanded(
                child: Text(
                  label,
                  style: look.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: CanvasStickyCardMetrics.bodyGap),
          // 正文吃掉剩余高度：便签高度由用户/AI 决定，正文按实际空间截断而不是
          // 写死行数，拉高便签时能多显示几行。
          Expanded(
            child: Text(
              body,
              style: look.bodyStyle,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }
}

/// 按 refType 取 phosphor 图标 asset 路径。
///
/// public 供 [CanvasResourcePicker] 与详情面板复用,避免重复映射。
String canvasRefTypeIcon(String refType) {
  return switch (refType) {
    canvasNodeRefTypeScreenplayScene => RevericIcons.movie_outlined,
    entityTypeCharacter => RevericIcons.smart_toy_outlined,
    entityTypeChapter => RevericIcons.description_outlined,
    entityTypeForeshadowing => RevericIcons.flag,
    canvasNodeRefTypeOutline => RevericIcons.format_list_numbered,
    entityTypeLocation => RevericIcons.location_on,
    entityTypeItem => RevericIcons.inventory_2_outlined,
    entityTypeFaction => RevericIcons.groups_outlined,
    entityTypeSkill => RevericIcons.lightning,
    entityTypeCreature => RevericIcons.bug_beetle_outlined,
    canvasNodeRefTypeDocument => RevericIcons.description_outlined,
    _ => RevericIcons.description_outlined,
  };
}

/// 按 refType 取本地化类型标签(复用 workspace section 文案)。
String canvasRefTypeLabel(BuildContext context, String refType) {
  return switch (refType) {
    canvasNodeRefTypeScreenplayScene => context.t(LocaleKeys.screenplayScenes),
    entityTypeCharacter => context.t(LocaleKeys.workspaceCharacters),
    entityTypeChapter => context.t(LocaleKeys.workspaceChapters),
    entityTypeForeshadowing => context.t(LocaleKeys.workspaceForeshadowings),
    canvasNodeRefTypeOutline => context.t(LocaleKeys.workspaceOutlines),
    entityTypeLocation => context.t(LocaleKeys.workspaceLore),
    entityTypeItem => context.t(LocaleKeys.workspaceItems),
    entityTypeFaction => context.t(LocaleKeys.workspaceFactions),
    entityTypeSkill => context.t(LocaleKeys.workspaceSkills),
    entityTypeCreature => context.t(LocaleKeys.workspaceCreatures),
    canvasNodeRefTypeDocument => context.t(LocaleKeys.workspaceMaterials),
    _ => refType,
  };
}

/// 按边类型取本地化标签。
String canvasEdgeTypeLabel(BuildContext context, String type) {
  return switch (type) {
    canvasEdgeTypeRelationship => context.t(
      LocaleKeys.canvasEdgeTypeRelationship,
    ),
    canvasEdgeTypeCausal => context.t(LocaleKeys.canvasEdgeTypeCausal),
    canvasEdgeTypeTimeline => context.t(LocaleKeys.canvasEdgeTypeTimeline),
    canvasEdgeTypeForeshadowPayoff => context.t(
      LocaleKeys.canvasEdgeTypeForeshadowPayoff,
    ),
    canvasEdgeTypeAssociation => context.t(
      LocaleKeys.canvasEdgeTypeAssociation,
    ),
    _ => type,
  };
}

/// 按边类型取一句话说明(选择器里帮作者选对语义)。
String canvasEdgeTypeDescription(BuildContext context, String type) {
  return switch (type) {
    canvasEdgeTypeRelationship => context.t(
      LocaleKeys.canvasEdgeDescRelationship,
    ),
    canvasEdgeTypeCausal => context.t(LocaleKeys.canvasEdgeDescCausal),
    canvasEdgeTypeTimeline => context.t(LocaleKeys.canvasEdgeDescTimeline),
    canvasEdgeTypeForeshadowPayoff => context.t(
      LocaleKeys.canvasEdgeDescForeshadowPayoff,
    ),
    canvasEdgeTypeAssociation => context.t(
      LocaleKeys.canvasEdgeDescAssociation,
    ),
    _ => '',
  };
}

/// 节点颜色的本地化名称(颜色选择器 tooltip)；自定义色直接显示 hex。
String canvasNodeColorLabel(BuildContext context, String value) {
  return switch (value) {
    canvasStickyColorSand => context.t(LocaleKeys.canvasStickyColorSand),
    canvasStickyColorSage => context.t(LocaleKeys.canvasStickyColorSage),
    canvasStickyColorRose => context.t(LocaleKeys.canvasStickyColorRose),
    canvasStickyColorStone => context.t(LocaleKeys.canvasStickyColorStone),
    canvasNodeColorRed => context.t(LocaleKeys.canvasNodeColorRed),
    canvasNodeColorOrange => context.t(LocaleKeys.canvasNodeColorOrange),
    canvasNodeColorYellow => context.t(LocaleKeys.canvasNodeColorYellow),
    canvasNodeColorGreen => context.t(LocaleKeys.canvasNodeColorGreen),
    canvasNodeColorTeal => context.t(LocaleKeys.canvasNodeColorTeal),
    canvasNodeColorBlue => context.t(LocaleKeys.canvasNodeColorBlue),
    canvasNodeColorPurple => context.t(LocaleKeys.canvasNodeColorPurple),
    canvasNodeColorPink => context.t(LocaleKeys.canvasNodeColorPink),
    _ => value,
  };
}
