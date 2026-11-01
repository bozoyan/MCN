// 职责: 统一普通操作按钮的语义、尺寸、图标与加载反馈，继承全局按钮主题。
// 关联文件:
//   lib/shared/theme/reveric_theme.dart
//   lib/shared/theme/reveric_spacing.dart
//   lib/shared/theme/reveric_icons.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// [standard] 用于表单与弹窗操作；[prominent] 只给页面唯一的主操作；
/// [compact] 用于工具区与行内操作。
enum RevericButtonSize { standard, prominent, compact }

enum _ButtonVariant { primary, secondary, text, danger }

/// 普通操作按钮；调用方持有异步状态，组件只展示 loading 并阻止再次点击。
class RevericButton extends StatelessWidget {
  const RevericButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.primary;

  const RevericButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.secondary;

  const RevericButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.text;

  /// 破坏性确认操作，沿用设计系统的删除语义色。
  const RevericButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.danger;

  final String label;
  final int? labelMaxLines;
  final VoidCallback? onPressed;
  final String? icon;
  final bool loading;
  final RevericButtonSize size;
  final _ButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = RevericTheme.colorsOf(context);
    final mobile = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final compact = size == RevericButtonSize.compact;
    final minimumHeight = switch (size) {
      RevericButtonSize.compact => RevericSizes.buttonHeightSm,
      RevericButtonSize.prominent => RevericSizes.buttonHeight,
      RevericButtonSize.standard =>
        mobile ? RevericSizes.buttonHeight : RevericSizes.buttonHeightDesktop,
    };
    final danger = _variant == _ButtonVariant.danger;
    final dangerBackground = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            colors.canvas.withValues(alpha: 0.2),
            colors.deletionBorder,
          )
        : colors.deletionBorder;
    final backgroundLuminance = dangerBackground.computeLuminance();
    double contrast(Color foreground) {
      final luminance = foreground.computeLuminance();
      return luminance > backgroundLuminance
          ? (luminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (luminance + 0.05);
    }

    // 主色按钮的 onAccent 不一定适合红色背景；从主题中选对比更高的文字色。
    final dangerForeground =
        contrast(colors.canvas) > contrast(colors.textPrimary)
        ? colors.canvas
        : colors.textPrimary;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, minimumHeight)),
      padding: compact
          ? const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: RevericSizes.buttonPaddingHSm),
            )
          : null,
      tapTargetSize: mobile
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: danger
          ? WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? dangerForeground.withValues(alpha: 0.7)
                  : dangerForeground;
            })
          : null,
      backgroundColor: danger
          ? WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? dangerBackground.withValues(alpha: 0.4)
                  : dangerBackground;
            })
          : null,
    );
    final child = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      labelMaxLines: labelMaxLines,
    );
    final callback = loading ? null : onPressed;
    return switch (_variant) {
      _ButtonVariant.primary || _ButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
      _ButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
      _ButtonVariant.text => TextButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
    };
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.labelMaxLines,
  });

  final String label;
  final int? labelMaxLines;
  final String? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: labelMaxLines,
      overflow: labelMaxLines == null ? null : TextOverflow.ellipsis,
    );
    final content = icon == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                icon!,
                color: DefaultTextStyle.of(context).style.color,
                size: RevericSizes.buttonIconSize,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Flexible(child: text),
            ],
          );
    if (!loading) {
      return content;
    }
    // 加载时隐藏内容但保留尺寸与语义，指示器居中覆盖，按钮宽度不随状态变化。
    return Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          maintainSemantics: true,
          child: content,
        ),
        SizedBox.square(
          dimension: RevericSizes.buttonIconSize,
          child: CircularProgressIndicator(
            strokeWidth: RevericSizes.buttonProgressStroke,
            color: DefaultTextStyle.of(context).style.color,
          ),
        ),
      ],
    );
  }
}
