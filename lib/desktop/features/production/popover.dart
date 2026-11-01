// 职责: 制片顶栏与画布浮层共用的弹层外壳、菜单行和底栏 pill；锚定弹层本身见 RevericPopover。
// 关联文件:
//   lib/desktop/features/production/spec_panel.dart
//   lib/desktop/features/production/style_button.dart
//   lib/desktop/features/production/composer.dart
//   lib/desktop/features/production/node_bar.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import '../../../shared/theme/canvas_colors.dart';
import '../../../shared/theme/theme.dart';

/// 弹层外壳：面板底色、边框、圆角和投影。
class ProductionPopoverPanel extends StatelessWidget {
  const ProductionPopoverPanel({
    super.key,
    required this.width,
    required this.child,
    this.maxHeight,
    this.padding = const EdgeInsets.all(RevericSpacing.xs),
    this.radius = RevericRadius.large,
  });

  final double width;
  final double? maxHeight;
  final EdgeInsets padding;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
        padding: padding,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: canvasGlassShadows(colors),
        ),
        child: child,
      ),
    );
  }
}

/// 弹层标题：粗体标题 + 一句灰色说明。
class ProductionPopoverHead extends StatelessWidget {
  const ProductionPopoverHead({super.key, required this.title, this.detail});
  final String title;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.xs,
        RevericSpacing.xxs,
        RevericSpacing.xs,
        RevericSpacing.sm,
      ),
      child: Text.rich(
        TextSpan(
          text: title,
          children: [
            if (detail != null)
              TextSpan(
                text: ' · $detail',
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

class ProductionPopoverDivider extends StatelessWidget {
  const ProductionPopoverDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(
      horizontal: RevericSpacing.xs,
      vertical: RevericSpacing.xxs,
    ),
    color: RevericTheme.colorsOf(context).borderSubtle,
  );
}

/// 弹层里的一行动作：图标 + 名称 + 右侧说明。
class ProductionPopoverItem extends StatelessWidget {
  const ProductionPopoverItem({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.meta,
  });
  final String label;
  final String? icon;
  final Widget? leading;
  final String? meta;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      hoverColor: colors.hover,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.xs,
            vertical: RevericSpacing.xxs,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: RevericSpacing.sm),
              ] else if (icon != null) ...[
                RevericIcon(icon!, size: 15, color: colors.textMuted),
                const SizedBox(width: RevericSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmallSemibold.copyWith(
                    color: onTap == null
                        ? colors.textSubtle
                        : colors.textPrimary,
                  ),
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  meta!,
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入框底栏与顶栏的无边框 pill：悬停或展开时铺一层 hover 底色。
class ProductionPill extends StatelessWidget {
  const ProductionPill({
    super.key,
    required this.child,
    required this.onTap,
    this.open = false,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
  });
  final Widget child;
  final VoidCallback? onTap;
  final bool open;
  final String? tooltip;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final radius = BorderRadius.circular(RevericRadius.large);
    final pill = Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: open ? colors.hover : null,
          borderRadius: radius,
        ),
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.hover,
          borderRadius: radius,
          // widthFactor 让 pill 只占内容宽度；放进 Flexible 时不会被撑满剩余空间。
          child: Container(
            height: 30,
            padding: padding,
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// 输入框底栏的方形图标按钮（＋ / @ / 运镜）。
class ProductionToolButton extends StatelessWidget {
  const ProductionToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.open = false,
  });
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool open;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return SizedBox(
      width: 30,
      child: ProductionPill(
        open: open,
        tooltip: tooltip,
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: RevericIcon(
          icon,
          size: 16,
          color: onTap == null ? colors.textSubtle : colors.textSecondary,
        ),
      ),
    );
  }
}

/// 输入框底栏右端的圆形发送键（生成 / 重做 / 取消）。
class ProductionSendButton extends StatelessWidget {
  const ProductionSendButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? colors.accent
            : colors.textPrimary.withValues(alpha: .08),
        shape: CircleBorder(
          side: enabled ? BorderSide.none : BorderSide(color: colors.border),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: colors.accentWarm,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 34,
            child: Center(
              child: RevericIcon(
                icon,
                size: 16,
                color: enabled ? colors.onAccent : colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// pill 末尾的展开箭头。
class ProductionCaret extends StatelessWidget {
  const ProductionCaret({super.key, required this.open, this.size = 10});
  final bool open;
  final double size;
  @override
  Widget build(BuildContext context) => RevericIcon(
    open ? RevericIcons.expand_less_rounded : RevericIcons.caret_down,
    size: size,
    color: RevericTheme.colorsOf(context).textMuted,
  );
}
