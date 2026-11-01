// 职责: AI 模式错误提示 — 在内容流中展示已中断状态与本地化错误原因。
// 关联文件:
//   lib/shared/localization/ai_run_failure_localization.dart
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/mobile/features/council/page_widgets.dart
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../localization/ai_run_failure_localization.dart';
import '../../localization/app_localization.dart';
import '../../models/ai_run_failure.dart';
import '../../theme/theme.dart';

class AiModeErrorNotice extends StatelessWidget {
  const AiModeErrorNotice({
    super.key,
    required this.title,
    required this.failure,
  });

  final String title;
  final AiRunFailure failure;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final message = localizeAiRunFailure(failure, context.t);

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RevericSpacing.lg),
        decoration: BoxDecoration(
          color: colors.warningBg.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(RevericRadius.x2l),
          border: Border.all(color: colors.warningText.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: RevericSpacing.xxs),
                  child: RevericIcon(
                    RevericIcons.warning_circle,
                    size: 18,
                    color: colors.warningText,
                  ),
                ),
                const SizedBox(width: RevericSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: typo.uiSmallSemibold.copyWith(
                          color: colors.warningText,
                        ),
                      ),
                      const SizedBox(height: RevericSpacing.xxs),
                      Text(
                        message,
                        style: typo.uiSmall.copyWith(
                          color: colors.warningText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
