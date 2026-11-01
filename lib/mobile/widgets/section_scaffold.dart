// 职责: 移动端分区列表共享骨架 — 空状态、圆角卡片列表（左滑删除与章节列表一致）、可选非点击 footer、状态点表头、正文预览，供各 section 面板复用。
// 关联文件:
//   lib/mobile/widgets/chapters_panel.dart
//   lib/mobile/widgets/section_panel.dart
//   lib/mobile/widgets/characters_panel.dart
//   lib/mobile/widgets/foreshadowings_panel.dart
//   lib/mobile/widgets/outlines_panel.dart
//   lib/mobile/widgets/maps_panel.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import '../../shared/components/reveric_placeholder.dart';
import '../../shared/components/reveric_button.dart';

import 'package:flutter_slidable/flutter_slidable.dart';

import '../../shared/theme/theme.dart';

/// 卡片正文预览的行高（仅在本模块内复用）。
const double _previewLineHeight = 1.45;

/// 左滑删除区占整行宽度的比例；卡片右角拉直进度须按此归一化。
const double _endActionExtentRatio = 0.26;

/// 列表页内容内边距（对齐章节列表与 designs/mobile ChaptersBody）。
const EdgeInsets mobileSectionListPadding = EdgeInsets.fromLTRB(
  RevericSpacing.x4l,
  RevericSpacing.md,
  RevericSpacing.x4l,
  RevericSpacing.x5l,
);

/// 卡片默认内边距。
const EdgeInsets mobileSectionCardPadding = EdgeInsets.symmetric(
  horizontal: RevericSpacing.lg,
  vertical: RevericSpacing.lg,
);

/// 顶部右对齐的新建按钮条（accent pill）。
class MobileSectionCreateBar extends StatelessWidget {
  const MobileSectionCreateBar({
    super.key,
    required this.label,
    required this.onTap,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onTap;

  /// 可选：透传到可点击区域，便于测试定位。
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x4l,
        0,
        RevericSpacing.x4l,
        RevericSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          key: buttonKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(RevericRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RevericIcon(RevericIcons.add, size: 16, color: colors.accent),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  label,
                  style: typo.uiSmallSemibold.copyWith(color: colors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 固定在列表底部的全宽次级操作按钮（用于设定/素材导入）。
class MobileSectionBottomAction extends StatelessWidget {
  const MobileSectionBottomAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = RevericIcons.add,
  });

  final String label;
  final VoidCallback onTap;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final borderRadius = BorderRadius.circular(RevericRadius.large);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        RevericSpacing.x4l,
        0,
        RevericSpacing.x4l,
        bottomInset + RevericSpacing.x2l,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: CustomPaint(
          foregroundPainter: _DashedRoundedBorderPainter(
            color: colors.accentWarm,
            radius: RevericRadius.large,
          ),
          child: SizedBox(
            height: RevericSizes.buttonHeight,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RevericIcon(icon, size: 16, color: colors.accentWarm),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  label,
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.accentWarm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + RevericSpacing.sm;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + RevericSpacing.xs;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}

/// 空分区占位：图标 + 标题 + 提示 + 新建按钮。
class MobileSectionEmptyState extends StatelessWidget {
  const MobileSectionEmptyState({
    super.key,
    required this.icon,
    required this.sectionLabel,
    required this.hint,
    required this.actionLabel,
    required this.onCreate,
    this.actionKey,
  });

  /// `RevericIcons` 常量（SVG 路径字符串）。
  final String icon;
  final String sectionLabel;
  final String hint;
  final String actionLabel;
  final VoidCallback onCreate;

  /// 可选：透传到新建按钮，便于测试定位。
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RevericPlaceholder.empty(
        icon: icon,
        title: sectionLabel,
        description: hint,
        action: RevericButton.primary(
          key: actionKey,
          label: actionLabel,
          onPressed: onCreate,
        ),
      ),
    );
  }
}

/// 列表卡片末尾 chevron（对齐设计稿 EntityListBody / CharactersBody）。
class MobileSectionTrailingChevron extends StatelessWidget {
  const MobileSectionTrailingChevron({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return RevericIcon(
      RevericIcons.chevron_right,
      size: 16,
      color: colors.textSubtle,
    );
  }
}

/// 列表卡片内的小型标签 chip。
class MobileSectionTagChip extends StatelessWidget {
  const MobileSectionTagChip({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // 注意: Container 一旦设置 alignment，在有界宽度约束下会撑满父级宽度。
    // 横向 Wrap 会给子级传入 maxWidth=父宽（有界），因此不能用 alignment 居中，
    // 否则每个 chip 会占满整行并各自换行。改用内边距撑出 pill 尺寸即可。
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Text(
        label,
        // pill 是单行的：宽度受限时省略，不换行撑破 chip。
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: typo.uiTiny.copyWith(
          color: foregroundColor ?? colors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

/// 设定实体列表左侧色块图标（物品/势力/世界观等）。
class MobileSectionIconBox extends StatelessWidget {
  const MobileSectionIconBox({
    super.key,
    required this.icon,
    this.size = 42,
    this.iconSize = 21,
    this.tint,
  });

  final String icon;
  final double size;
  final double iconSize;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final bg = tint ?? colors.accent.withValues(alpha: 0.18);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: RevericIcon(icon, size: iconSize, color: colors.accentWarm),
    );
  }
}

/// 可点击的圆角列表卡片；传入 [onDelete] 后启用左滑删除（与章节列表 SwipeRow 一致）。
class MobileSectionCard extends StatefulWidget {
  const MobileSectionCard({
    super.key,
    required this.onTap,
    required this.child,
    this.padding = mobileSectionCardPadding,
    this.cardKey,
    this.onDelete,
    this.deleteLabel,
    this.onLongPress,
    this.footer,
  });

  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 可选：透传到可点击区域，便于测试定位。
  final Key? cardKey;

  /// 可选：启用左滑删除。点击删除按钮时调用（调用方负责确认 + 删除）。
  final VoidCallback? onDelete;

  /// 删除按钮文案（启用 [onDelete] 时建议提供）。
  final String? deleteLabel;

  /// 可选：长按回调（例如弹出次要操作 sheet）。
  final VoidCallback? onLongPress;

  /// 可选：卡片底部非点击区域，用于放置独立操作，避免与 [onTap] 竞争手势。
  final Widget? footer;

  @override
  State<MobileSectionCard> createState() => _MobileSectionCardState();
}

class _MobileSectionCardState extends State<MobileSectionCard>
    with TickerProviderStateMixin {
  SlidableController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.onDelete != null) {
      _controller = SlidableController(this);
    }
  }

  @override
  void didUpdateWidget(covariant MobileSectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onDelete != null && _controller == null) {
      _controller = SlidableController(this);
    } else if (widget.onDelete == null && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final controller = _controller;

    Widget cardBody({required BorderRadius borderRadius}) {
      if (widget.footer != null) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: borderRadius,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: widget.cardKey,
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                borderRadius: borderRadius,
                child: Padding(padding: widget.padding, child: widget.child),
              ),
              widget.footer!,
            ],
          ),
        );
      }
      return InkWell(
        key: widget.cardKey,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: borderRadius,
        child: Container(
          width: double.infinity,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: borderRadius,
            border: Border.all(color: colors.border),
          ),
          child: widget.child,
        ),
      );
    }

    if (widget.onDelete == null || controller == null) {
      return cardBody(
        borderRadius: BorderRadius.circular(RevericRadius.large),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Slidable(
        controller: controller,
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: _endActionExtentRatio,
          children: [
            CustomSlidableAction(
              onPressed: (_) => widget.onDelete!(),
              backgroundColor: colors.error.withValues(alpha: 0.88),
              borderRadius: BorderRadius.zero,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIcon(
                    RevericIcons.delete_outline,
                    size: 20,
                    color: colors.onAccent,
                  ),
                  if (widget.deleteLabel != null) ...[
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      widget.deleteLabel!,
                      style: typo.uiTiny.copyWith(color: colors.onAccent),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: controller.animation,
          builder: (context, _) {
            final open = (-controller.ratio / _endActionExtentRatio).clamp(
              0.0,
              1.0,
            );
            final rightRadius = RevericRadius.large * (1.0 - open);
            final borderRadius = BorderRadius.only(
              topLeft: Radius.circular(RevericRadius.large),
              bottomLeft: Radius.circular(RevericRadius.large),
              topRight: Radius.circular(rightRadius),
              bottomRight: Radius.circular(rightRadius),
            );
            return cardBody(borderRadius: borderRadius);
          },
        ),
      ),
    );
  }
}

/// 列表页通用骨架：顶部新建条 + 空状态/`ListView.separated`。
///
/// 仅适用于扁平列表分区；树形分区（如地图）请直接组合
/// [MobileSectionCreateBar] / [MobileSectionEmptyState] / [MobileSectionCard]。
class MobileSectionListScaffold extends StatelessWidget {
  const MobileSectionListScaffold({
    super.key,
    required this.createLabel,
    required this.onCreate,
    required this.emptyIcon,
    required this.emptySectionLabel,
    required this.emptyHint,
    required this.itemCount,
    required this.itemBuilder,
    this.showCreateBar = true,
    this.header,
    this.bottomAction,
  });

  final String createLabel;
  final VoidCallback onCreate;
  final String emptyIcon;
  final String emptySectionLabel;
  final String emptyHint;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? header;
  final Widget? bottomAction;

  /// 是否在列表顶部渲染新建条；由外部标题栏承载新建入口时置 false，
  /// 空状态引导按钮仍保留（走 [onCreate]）。
  final bool showCreateBar;

  /// 可选：新建条与列表之间的附加区域（例如目录面包屑）。

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showCreateBar)
          MobileSectionCreateBar(label: createLabel, onTap: onCreate),
        ?header,
        Expanded(
          child: itemCount == 0
              ? MobileSectionEmptyState(
                  icon: emptyIcon,
                  sectionLabel: emptySectionLabel,
                  hint: emptyHint,
                  actionLabel: createLabel,
                  onCreate: onCreate,
                )
              : ListView.separated(
                  padding: mobileSectionListPadding,
                  itemCount: itemCount,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: RevericSpacing.sm),
                  itemBuilder: itemBuilder,
                ),
        ),
        ?bottomAction,
      ],
    );
  }
}

/// 卡片表头：状态色点 + 标题（占满）+ 末尾状态文案。
class MobileSectionStatusHeader extends StatelessWidget {
  const MobileSectionStatusHeader({
    super.key,
    required this.statusColor,
    required this.title,
    required this.statusLabel,
  });

  final Color statusColor;
  final String title;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        MobileSectionTagChip(
          label: statusLabel,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          foregroundColor: statusColor,
        ),
      ],
    );
  }
}

/// 卡片正文预览：空内容回退到占位文案并切到更弱的颜色。
class MobileSectionPreviewText extends StatelessWidget {
  const MobileSectionPreviewText({
    super.key,
    required this.preview,
    required this.emptyPlaceholder,
    this.maxLines = 2,
  });

  final String preview;
  final String emptyPlaceholder;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isEmpty = preview.isEmpty;
    return Text(
      isEmpty ? emptyPlaceholder : preview,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: typo.uiSmall.copyWith(
        color: isEmpty ? colors.textSubtle : colors.textMuted,
        height: _previewLineHeight,
      ),
    );
  }
}
