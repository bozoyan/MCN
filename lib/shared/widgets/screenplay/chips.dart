// 职责: 剧本区域的标签、状态徽章与八分之一页排版件。
// 关联文件:
//   lib/desktop/features/screenplay/outline.dart
//   lib/desktop/features/screenplay/scenes.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/screenplay.dart';
import '../../theme/theme.dart';

enum ScreenplayChipTone {
  /// 1px 描边 + surface 底，默认形态。
  outlined,

  /// 无描边 + surfaceDim 底，用于密集堆叠的次要信息（人物名、场号）。
  plain,
}

/// `.sp-chip` —— 24 高的小标签，可选前置图标。
class ScreenplayChip extends StatelessWidget {
  const ScreenplayChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = ScreenplayChipTone.outlined,
    this.onTap,
  });

  final String label;
  final String? icon;
  final ScreenplayChipTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final plain = tone == ScreenplayChipTone.plain;
    final chip = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
      decoration: BoxDecoration(
        color: plain ? colors.surfaceDim : colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(
          color: plain ? Colors.transparent : colors.borderInput,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            RevericIcon(icon, size: 12, color: colors.textMuted),
            const SizedBox(width: RevericSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiTiny.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return chip;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: chip,
    );
  }
}

/// `.sp-state` —— 场次阶段徽章。定稿走 addition 语义色，草稿走 selected 底。
class ScreenplayStageBadge extends StatelessWidget {
  const ScreenplayStageBadge({super.key, required this.stage});

  final String stage;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isFinal = stage == screenplayStageFinal;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
      decoration: BoxDecoration(
        color: isFinal ? colors.additionBg : colors.selected,
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      // Wrap 给的是松约束，Container 一旦带 alignment 就会撑满整行；
      // 这里用 Row(min) 收宽度，同时保持文字垂直居中。
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t(
              isFinal ? LocaleKeys.screenplayFinal : LocaleKeys.screenplayDraft,
            ),
            style: typo.uiTiny.copyWith(
              fontWeight: FontWeight.w500,
              color: isFinal ? colors.additionBorder : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _superscripts = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷'];

/// 把 `pageEighths` 排成真正的带分数：6 → `⁶⁄₈`，14 → `1⁶⁄₈`。
///
/// 直接写 "1 6/8" 会被读成「16/8」，所以用上标 / 分数斜线 / 下标凑出带分数，
/// 而不是靠空格分隔两个普通数字。
String screenplayPageEighthsText(int pageEighths) {
  final whole = pageEighths ~/ 8;
  final numerator = pageEighths % 8;
  if (numerator == 0) {
    return '$whole';
  }
  final fraction = '${_superscripts[numerator]}⁄₈';
  return whole == 0 ? fraction : '$whole$fraction';
}

/// `.sp-pages` —— 带分数页数 + 可选单位。
class ScreenplayPagesText extends StatelessWidget {
  const ScreenplayPagesText({
    super.key,
    required this.pageEighths,
    this.showUnit = true,
    this.style,
  });

  final int pageEighths;
  final bool showUnit;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final base = style ?? typo.uiTiny.copyWith(color: colors.textMuted);
    final value = screenplayPageEighthsText(pageEighths);
    final unit = showUnit
        ? ' ${context.t(LocaleKeys.screenplayPagesUnit)}'
        : '';
    return Text(
      '$value$unit',
      style: base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
