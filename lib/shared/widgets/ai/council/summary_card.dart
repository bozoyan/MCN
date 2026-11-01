// 职责: 议会总结卡片与「总结生成中」占位，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/widgets/ai/typing_dots.dart
//   lib/shared/widgets/ai/markdown_text.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/agent_council_models.dart';
import '../../../theme/theme.dart';
import '../chat/chat_message_parts.dart' show CopyIconButton;
import '../markdown_text.dart';
import '../typing_dots.dart';

BoxDecoration _summaryDecoration(RevericColors colors) => BoxDecoration(
  color: colors.accent.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(RevericRadius.xl),
  border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
);

class CouncilSummaryCard extends StatelessWidget {
  const CouncilSummaryCard({
    super.key,
    required this.summary,
    required this.isOutdated,
  });

  final CouncilSummary summary;

  /// 总结之后又追加了讨论轮次。
  final bool isOutdated;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = !isOutdated
        ? context.t(LocaleKeys.councilSummaryTitle)
        : summary.coveredThroughRound > 0
        ? context.t(
            LocaleKeys.councilPreviousSummaryThroughRound,
            namedArgs: {'round': '${summary.coveredThroughRound}'},
          )
        : context.t(LocaleKeys.councilPreviousSummary);
    return Container(
      margin: const EdgeInsets.only(bottom: RevericSpacing.lg),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: _summaryDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.summarize_rounded,
                size: 18,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: typo.uiSemibold.copyWith(color: colors.accent),
                ),
              ),
              CopyIconButton(text: summary.content),
            ],
          ),
          const SizedBox(height: RevericSpacing.md),
          AiMarkdownText(
            summary.content,
            style: typo.ui.copyWith(color: colors.textPrimary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class CouncilSummaryPending extends StatelessWidget {
  const CouncilSummaryPending({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: RevericSpacing.lg),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: _summaryDecoration(colors),
      child: Row(
        children: [
          Text(
            context.t(LocaleKeys.councilSummaryGenerating),
            style: typo.uiSmall.copyWith(color: colors.accent),
          ),
          const SizedBox(width: RevericSpacing.sm),
          TypingDots(color: colors.accent),
        ],
      ),
    );
  }
}
