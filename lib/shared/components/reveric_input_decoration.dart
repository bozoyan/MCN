// 职责: Reveric 表单装饰 — 提供 text field 与 form dropdown 共享的 InputDecoration。
// 关联文件:
//   lib/shared/components/reveric_dropdowns.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../theme/theme.dart';

InputDecoration revericInputDecoration(
  BuildContext context, {
  String? label,
  String? hintText,
  String? errorText,
  String? suffixText,
  TextStyle? suffixStyle,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
  Widget? prefixIcon,
  BoxConstraints? prefixIconConstraints,
  Color? fillColor,
  double radius = RevericRadius.large,
  EdgeInsetsGeometry? contentPadding,
  int? errorMaxLines,
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  return InputDecoration(
    labelText: label,
    hintText: hintText,
    errorText: errorText,
    errorMaxLines: errorMaxLines,
    suffixText: suffixText,
    suffixStyle: suffixStyle,
    suffixIcon: suffixIcon,
    suffixIconConstraints: suffixIconConstraints,
    prefixIcon: prefixIcon,
    // 不给约束时 Material 会套 48×48 下限，图标会被 SizedBox 的 enforce 撑大。
    prefixIconConstraints: prefixIconConstraints,
    labelStyle: typo.ui.copyWith(color: colors.textSecondary),
    hintStyle: typo.ui.copyWith(color: colors.textSubtle),
    filled: true,
    fillColor: fillColor ?? colors.surfaceContainerHigh,
    contentPadding: contentPadding,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colors.borderInput),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colors.borderInput),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colors.accent),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colors.warningText),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colors.warningText),
    ),
  );
}
