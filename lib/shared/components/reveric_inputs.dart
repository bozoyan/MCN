// 职责: Reveric 输入控件 — 提供设置/属性面板中的 inline 输入与动作组合。
// 关联文件:
//   lib/shared/components/reveric_input_decoration.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'reveric_input_decoration.dart';

class RevericInlineActionInput extends StatelessWidget {
  const RevericInlineActionInput({
    super.key,
    required this.controller,
    required this.hintText,
    required this.actionLabel,
    required this.onActionPressed,
    this.enabled = true,
    this.fillColor,
    this.height = RevericSizes.buttonHeight,
  });

  final TextEditingController controller;
  final String hintText;
  final String actionLabel;
  final VoidCallback onActionPressed;
  final bool enabled;
  final Color? fillColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlignVertical: TextAlignVertical.center,
              style: typo.ui.copyWith(color: colors.textPrimary),
              decoration: revericInputDecoration(
                context,
                hintText: hintText,
                fillColor: fillColor ?? colors.surfaceDim,
                radius: RevericRadius.medium,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.md,
                ),
              ),
              onSubmitted: enabled ? (_) => onActionPressed() : null,
            ),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        SizedBox(
          height: height,
          child: FilledButton(
            onPressed: enabled ? onActionPressed : null,
            style: height < RevericSizes.buttonHeight
                ? FilledButton.styleFrom(
                    minimumSize: Size(0, height),
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSizes.buttonPaddingHSm,
                    ),
                  )
                : null,
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}
