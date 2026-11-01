// 职责: 画布浮动控制簇的容器与按钮，构思画布和制作画布共用同一套外观。
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/glass.dart
//   lib/desktop/features/production/board.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../../shared/theme/canvas_colors.dart';
import '../../../../shared/theme/theme.dart';
import 'glass.dart';

/// 画布浮动控制簇的共享容器：毛玻璃浮层。竖排是圆角条，横排是 40 高的胶囊，
/// 里面是 28 的圆形按钮，分组之间只留空隙不画线。
class CanvasFloatingCluster extends StatelessWidget {
  const CanvasFloatingCluster({
    super.key,
    required this.children,
    this.axis = Axis.vertical,
  });

  final List<Widget> children;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return CanvasGlass(
      radius: horizontal ? RevericRadius.capsule : RevericRadius.pill,
      padding: horizontal
          ? const EdgeInsets.all(RevericSpacing.xs)
          : const EdgeInsets.symmetric(vertical: RevericSpacing.xxs),
      child: _ClusterAxis(
        axis: axis,
        child: Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// 让按钮知道分隔线画在上沿还是左沿。
class _ClusterAxis extends InheritedWidget {
  const _ClusterAxis({required this.axis, required super.child});
  final Axis axis;

  static Axis of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ClusterAxis>()?.axis ??
      Axis.vertical;

  @override
  bool updateShouldNotify(_ClusterAxis old) => old.axis != axis;
}

/// 画布浮动控制簇的共享按钮：图标 + Tooltip + hover 反馈；[selected] 表示对应面板已展开。
class CanvasFloatingButton extends StatefulWidget {
  const CanvasFloatingButton({
    super.key,
    this.icon = '',
    this.tooltip,
    this.onTap,
    this.danger = false,
    this.divider = false,
    this.selected = false,
    this.child,
    this.axis,
  });

  final String icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool danger;

  /// 与前一组按钮分开：竖排在上沿画分隔线，横排在左侧留一段空隙。
  final bool divider;
  final bool selected;

  /// 替换图标的内容；横排时按内容宽度自适应（如缩放百分比）。
  final Widget? child;

  /// 排布方向；不给时跟随所在的 [CanvasFloatingCluster]。放进别的毛玻璃胶囊时显式指定。
  final Axis? axis;

  @override
  State<CanvasFloatingButton> createState() => _CanvasFloatingButtonState();
}

class _CanvasFloatingButtonState extends State<CanvasFloatingButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final horizontal =
        (widget.axis ?? _ClusterAxis.of(context)) == Axis.horizontal;
    final enabled = widget.onTap != null;
    final fg = widget.danger
        ? colors.deletionBorder
        : widget.selected
        ? colors.accentWarm
        : _hovered && enabled
        ? colors.textPrimary
        : colors.textSecondary;
    final hovered = _hovered && enabled;
    final Widget content;
    if (horizontal) {
      content = Padding(
        padding: EdgeInsets.only(
          left: widget.divider ? RevericSpacing.xs + 1 : 1,
          right: 1,
        ),
        child: AnimatedContainer(
          duration: CanvasMotion.hover,
          curve: CanvasMotion.curve,
          height: _compact,
          constraints: const BoxConstraints(minWidth: _compact),
          padding: widget.child == null
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
          decoration: BoxDecoration(
            color: widget.selected
                ? canvasGlassFill(colors, raised: true)
                : hovered
                ? canvasGlassHover(colors)
                : canvasGlassHover(colors).withValues(alpha: 0),
            border: Border.all(
              color: widget.selected
                  ? canvasGlassBorder(colors)
                  : canvasGlassBorder(colors).withValues(alpha: 0),
            ),
            borderRadius: BorderRadius.circular(RevericRadius.capsule),
          ),
          child: Center(
            widthFactor: 1,
            child:
                widget.child ??
                RevericIcon(
                  widget.icon,
                  size: 16,
                  color: widget.danger
                      ? colors.deletionBorder
                      : !enabled
                      ? colors.textSubtle
                      : widget.selected || hovered
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
          ),
        ),
      );
    } else {
      content = _vertical(colors, fg);
    }
    // 悬停底色由上面的动画接管，InkWell 只保留点击、焦点和按钮语义。
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        borderRadius: BorderRadius.circular(
          horizontal ? RevericRadius.capsule : RevericRadius.x2l,
        ),
        hoverColor: colors.hover.withValues(alpha: 0),
        highlightColor: colors.hover.withValues(alpha: 0),
        child: content,
      ),
    );
    if (widget.tooltip == null || widget.tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: widget.tooltip, child: button);
  }

  static const double _compact = 28;

  Widget _vertical(RevericColors colors, Color fg) {
    final enabled = widget.onTap != null;
    final line = BorderSide(color: canvasGlassBorder(colors));
    return Container(
      width: 40,
      height: 38,
      decoration: BoxDecoration(
        border: Border(top: widget.divider ? line : BorderSide.none),
      ),
      padding: const EdgeInsets.all(RevericSpacing.xxs),
      child: AnimatedContainer(
        duration: CanvasMotion.hover,
        curve: CanvasMotion.curve,
        decoration: BoxDecoration(
          color: widget.selected
              ? colors.selected
              : _hovered && enabled
              ? colors.hover.withValues(alpha: .7)
              : colors.hover.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(RevericRadius.x2l),
        ),
        child: Center(
          child:
              widget.child ??
              AnimatedScale(
                scale: _hovered && enabled ? 1.08 : 1,
                duration: CanvasMotion.fast,
                curve: CanvasMotion.curve,
                child: RevericIcon(widget.icon, size: 17, color: fg),
              ),
        ),
      ),
    );
  }
}
