// 职责: 展示「标签 数值 单位」一行内联统计，供剧本概览卡底统计条使用。
// 关联文件:
//   lib/desktop/features/screenplay/overview_cards.dart
//   lib/mobile/features/screenplay/overview_cards.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class ScreenplayInlineStat extends StatelessWidget {
  const ScreenplayInlineStat({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: typo.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(unit, style: typo.uiTiny.copyWith(color: colors.textSubtle)),
      ],
    );
  }
}
