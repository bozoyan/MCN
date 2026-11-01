// 职责: 集中派生剧本正文与缩略图的排版样式，避免各处散落 copyWith 尺寸。
// 关联文件:
//   lib/desktop/features/screenplay/script_elements.dart
//   lib/desktop/features/screenplay/scenes.dart
//   lib/shared/theme/theme.dart
//   designs/desktop/screenplay/screenplay.css
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// 剧本排版样式。字号与行高来自 `designs/desktop/screenplay/screenplay.css`
/// 的 `.sp-el--*`，全部由 theme 的 body / bodySmall / ui 派生，颜色一律取 token。
///
/// 括号提示刻意**不用** `FontStyle.italic`：中文字体没有 italic face，
/// macOS/iOS 会由 CoreText 合成错切，Android 可能直接忽略，同一份代码两端不一致。
/// 区分靠全角括号 + 缩进 + 更小字号 + 更浅颜色。
class ScreenplayTextStyles {
  const ScreenplayTextStyles({
    required this.sceneHeading,
    required this.sceneNumber,
    required this.sceneCondition,
    required this.sceneSeparator,
    required this.cast,
    required this.castNames,
    required this.action,
    required this.actionMarker,
    required this.character,
    required this.characterExtension,
    required this.parenthetical,
    required this.dialogue,
    required this.transition,
    required this.subtitle,
    required this.note,
    required this.notePrefix,
    required this.placeholder,
  });

  factory ScreenplayTextStyles.of(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return ScreenplayTextStyles(
      sceneHeading: typo.body.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: colors.textPrimary,
      ),
      sceneNumber: typo.body.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: colors.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      sceneCondition: typo.body.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: colors.textPrimary,
      ),
      sceneSeparator: typo.body.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: colors.textSubtle,
      ),
      cast: typo.bodySmall.copyWith(height: 1.6, color: colors.textMuted),
      castNames: typo.bodySmall.copyWith(
        height: 1.6,
        color: colors.textSecondary,
      ),
      action: typo.body.copyWith(color: colors.textPrimary),
      actionMarker: typo.body.copyWith(
        fontSize: 11,
        height: 1,
        color: colors.textSubtle,
      ),
      character: typo.body.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.6,
        color: colors.textPrimary,
      ),
      characterExtension: typo.bodySmall.copyWith(
        height: 1.6,
        color: colors.textMuted,
      ),
      parenthetical: typo.bodySmall.copyWith(
        height: 1.6,
        color: colors.textMuted,
      ),
      dialogue: typo.body.copyWith(color: colors.textPrimary),
      transition: typo.bodySmall.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.6,
        letterSpacing: 2,
        color: colors.textSecondary,
      ),
      subtitle: typo.body.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.7,
        letterSpacing: 4,
        color: colors.textSecondary,
      ),
      note: typo.ui.copyWith(height: 1.7, color: colors.textMuted),
      notePrefix: typo.ui.copyWith(
        height: 1.7,
        fontWeight: FontWeight.w600,
        color: colors.blockquoteBorder,
      ),
      placeholder: typo.body.copyWith(color: colors.textSubtle),
    );
  }

  final TextStyle sceneHeading;
  final TextStyle sceneNumber;
  final TextStyle sceneCondition;
  final TextStyle sceneSeparator;
  final TextStyle cast;
  final TextStyle castNames;
  final TextStyle action;
  final TextStyle actionMarker;
  final TextStyle character;
  final TextStyle characterExtension;
  final TextStyle parenthetical;
  final TextStyle dialogue;
  final TextStyle transition;
  final TextStyle subtitle;
  final TextStyle note;
  final TextStyle notePrefix;
  final TextStyle placeholder;
}

/// 场次卡顶部那块正文缩略的排版 —— 与正文同一套字体，只是压到 8.5px，
/// 让作者一眼认出「这一场长什么样」，而不是读它。
class ScreenplayPeekTextStyles {
  const ScreenplayPeekTextStyles({
    required this.line,
    required this.heading,
    required this.character,
    required this.parenthetical,
  });

  factory ScreenplayPeekTextStyles.of(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final base = typo.bodySmall.copyWith(fontSize: 8.5, height: 1.85);
    return ScreenplayPeekTextStyles(
      line: base.copyWith(color: colors.textMuted),
      heading: base.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.textSecondary,
      ),
      character: base.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.textSecondary,
      ),
      parenthetical: base.copyWith(color: colors.textSubtle),
    );
  }

  final TextStyle line;
  final TextStyle heading;
  final TextStyle character;
  final TextStyle parenthetical;
}
