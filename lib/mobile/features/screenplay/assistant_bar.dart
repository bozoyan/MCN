// 职责: 在剧本正文底部显示当前集总字数、台词字数、实际自动保存时间和 AI 助手入口。
// 关联文件:
//   lib/mobile/features/screenplay/document.dart
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/widgets/screenplay/document_session.dart
//   lib/shared/models/screenplay_element.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/widgets/screenplay/document_session.dart';
import '../../../shared/models/screenplay_element.dart';
import '../../../shared/services/screenplay_metrics.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/utils/text_unit_count.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class MobileScreenplayAssistantBar extends HookWidget {
  const MobileScreenplayAssistantBar({
    super.key,
    required this.onOpenAssistant,
    required this.session,
  });

  final VoidCallback onOpenAssistant;
  final ScreenplayDocumentSession? session;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final elements = useListenableSelector(
      session?.controller,
      () => session?.controller.value,
    );
    final counts = useMemoized(() {
      if (elements == null) {
        return null;
      }
      var dialogueWords = 0;
      for (final element in elements) {
        if (element.type == ScreenplayElementType.dialogue) {
          dialogueWords += countTextUnits(element.text);
        }
      }
      return (
        words: ScreenplayMetrics.calculate(elements).wordCount,
        dialogueWords: dialogueWords,
      );
    }, [elements]);
    final languageCode = Localizations.localeOf(context).languageCode;
    String formatCount(int? count) => count == null
        ? '—'
        : formatCompactWordCount(count, languageCode: languageCode);
    final summary = [
      context.t(
        LocaleKeys.workspaceWordCount,
        namedArgs: {'count': formatCount(counts?.words)},
      ),
      context.t(
        LocaleKeys.screenplayDialogueWordCount,
        namedArgs: {'count': formatCount(counts?.dialogueWords)},
      ),
    ].join(' · ');
    useListenable(session?.queue);
    final savedAt = session?.lastSavedAt;
    final statusText = savedAt == null
        ? context.t(LocaleKeys.screenplayAutosaveOn)
        : context.t(
            LocaleKeys.mobileEditorAutosaveAt,
            namedArgs: {
              'time':
                  '${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}',
            },
          );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      padding: EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.md,
        RevericSpacing.x2l,
        MediaQuery.viewPaddingOf(context).bottom + RevericSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: RevericSpacing.xxs),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiTiny.copyWith(color: colors.textSubtle),
                      ),
                    ),
                    const SizedBox(width: RevericSpacing.xs),
                    SizedBox.square(
                      dimension: RevericSpacing.md,
                      child: session?.queue.isSaving == true
                          ? CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textSubtle,
                              semanticsLabel: context.t(
                                LocaleKeys.mobileEditorSaving,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          FilledButton.icon(
            onPressed: onOpenAssistant,
            icon: RevericIcon(
              RevericIcons.auto_awesome,
              size: 18,
              color: colors.onAccent,
            ),
            label: Text(context.t(LocaleKeys.mobileEditorAiAssistant)),
          ),
        ],
      ),
    );
  }
}
