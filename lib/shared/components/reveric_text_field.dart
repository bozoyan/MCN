// 职责: Reveric 通用文本输入 — 单行/多行文本框，可选标签与辅助说明
// 关联文件:
//   lib/shared/components/reveric_input_decoration.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'reveric_input_decoration.dart';

/// 通用文本输入控件，覆盖表单与属性面板的单行/多行输入。
///
/// 浅色 surface 填充 + 细边框，
/// 聚焦时边框变为 accent。多行模式下顶部对齐，单行模式垂直居中。
class RevericTextField extends StatelessWidget {
  const RevericTextField({
    super.key,
    this.controller,
    this.fieldKey,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.errorMaxLines = 2,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.multiline = false,
    this.minLines = 4,
    this.maxLines = 8,
    this.height = RevericSizes.fieldHeight,
    this.fillColor,
    this.suffixIcon,
    this.suffixIconConstraints,
    this.autofocus = false,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.style,
    this.textAlign = TextAlign.start,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofillHints,
    this.restorationId,
  });

  /// 文本控制器；为空时使用内部非受控状态。
  final TextEditingController? controller;

  /// 应用到内部 [TextField] 的 key，便于测试定位输入框本体。
  final Key? fieldKey;

  /// 字段上方的标签文案。为空则不渲染标签。
  final String? label;

  /// 占位提示文案。
  final String? hintText;

  /// 字段下方的辅助说明文案。
  final String? helperText;

  /// 错误文案；非空时边框与文案使用错误色。
  final String? errorText;

  /// 错误文案最大行数。
  final int errorMaxLines;

  final bool enabled;
  final bool readOnly;

  /// 是否隐藏输入内容（密码、API Key 等）。多行模式下被忽略。
  final bool obscureText;

  /// 是否为多行输入。
  final bool multiline;

  /// 多行模式下的最小行数。
  final int minLines;

  /// 多行模式下的最大行数；为空表示不限。
  final int? maxLines;

  /// 单行模式下的固定高度。
  final double height;

  final Color? fillColor;
  final Widget? suffixIcon;

  /// suffix 图标区域约束；为空时使用 Material 默认（最小 48×48）。
  /// 传入更紧的约束可避免小图标占据过大留白。
  final BoxConstraints? suffixIconConstraints;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 点击输入框以外区域时触发；「失焦即提交」的随手输入用它代替保存按钮。
  final TapRegionCallback? onTapOutside;

  /// 覆盖默认的 [RevericTypography.ui]；长提示词等可传 [RevericTypography.uiSmall]。
  final TextStyle? style;

  /// 输入文本与占位提示的水平对齐方式；hero 标题类输入可传 [TextAlign.center]。
  final TextAlign textAlign;

  final bool autocorrect;
  final bool enableSuggestions;
  final Iterable<String>? autofillHints;

  /// 文本编辑状态的 restoration id；透传给内部 [TextField]。
  final String? restorationId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final hasError = errorText != null;

    var decoration = revericInputDecoration(
      context,
      hintText: hintText,
      fillColor: fillColor ?? colors.surfaceContainerHigh,
      suffixIcon: suffixIcon,
      suffixIconConstraints: suffixIconConstraints,
      radius: RevericRadius.large,
      contentPadding: multiline
          ? const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.md,
            )
          : const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
    );
    if (hasError) {
      // 错误态仅改边框颜色；错误文案在输入框下方单独渲染（见下方 Column），
      // 不走 InputDecoration 内置 error 槽，避免单行模式下固定高度被挤压成胶囊。
      final errorBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        borderSide: BorderSide(color: colors.error),
      );
      decoration = decoration.copyWith(
        border: errorBorder,
        enabledBorder: errorBorder,
        focusedBorder: errorBorder,
      );
    }

    final field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: !multiline && obscureText,
      autofocus: autofocus,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      autofillHints: autofillHints,
      restorationId: restorationId,
      keyboardType:
          keyboardType ?? (multiline ? TextInputType.multiline : null),
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      minLines: multiline ? minLines : 1,
      maxLines: multiline ? maxLines : 1,
      textAlign: textAlign,
      textAlignVertical: multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: (style ?? typo.ui).copyWith(
        color: enabled ? colors.textPrimary : colors.textMuted,
        height: style?.height ?? 1.6,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      decoration: decoration,
    );

    final input = multiline ? field : SizedBox(height: height, child: field);

    // 无论有没有 label / helper / 错误，都返回同一形状的 Column：输入框在 children 中的
    // 位置只由 label 是否存在决定（调用点固定），错误与辅助文案只在末尾增删。
    // 曾经的「无 label 且无错误时直接返回 input」快捷分支会让 errorText 一翻转就改变树形状，
    // TextField 的 element 被销毁重建、text input connection 断开重连，macOS 随即
    // discardMarkedText，用户正在组词的拼音被丢掉（首个拼音字母消失）。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.xs),
        ],
        input,
        if (hasError) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(
            errorText!,
            maxLines: errorMaxLines,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSmall.copyWith(color: colors.error),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(
            helperText!,
            style: typo.uiTiny.copyWith(color: colors.textSubtle),
          ),
        ],
      ],
    );
  }
}
