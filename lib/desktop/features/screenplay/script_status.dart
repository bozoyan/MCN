// 职责: 为桌面工作区底栏提供当前集的剧本字数统计。
// 关联文件:
//   lib/desktop/features/screenplay/script.dart
//   lib/desktop/features/screenplay/chrome.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/models/screenplay_element.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/utils/text_unit_count.dart';
import 'chrome.dart';

class ScreenplayScriptStatusItems extends ConsumerWidget {
  const ScreenplayScriptStatusItems({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final episodeId = workspace.episodeId;
    final previews = episodeId == null
        ? const <EpisodeScriptScenePreview>[]
        : ref
                  .watch(
                    screenplayEpisodeScriptPreviewProvider(path, episodeId),
                  )
                  .value ??
              const <EpisodeScriptScenePreview>[];
    final languageCode = Localizations.localeOf(context).languageCode;
    final wordCount = previews.fold<int>(
      0,
      (sum, preview) => sum + preview.scene.wordCount,
    );
    final dialogueWordCount = previews.fold<int>(
      0,
      (sum, preview) =>
          sum +
          preview.elements
              .where(
                (element) => element.type == ScreenplayElementType.dialogue,
              )
              .fold<int>(
                0,
                (sum, element) => sum + countTextUnits(element.text),
              ),
    );
    return Wrap(
      spacing: RevericSpacing.lg,
      runSpacing: RevericSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ScreenplayStatusItem(
          icon: RevericIcons.check_circle_outline,
          label: context.t(LocaleKeys.screenplayAutosaveOn),
        ),
        ScreenplayStatusItem(
          icon: RevericIcons.text_fields_outlined,
          label: context.t(
            LocaleKeys.workspaceWordCount,
            namedArgs: {
              'count': formatCompactWordCount(
                wordCount,
                languageCode: languageCode,
              ),
            },
          ),
        ),
        ScreenplayStatusItem(
          icon: RevericIcons.chat_outlined,
          label: context.t(
            LocaleKeys.screenplayDialogueWordCount,
            namedArgs: {
              'count': formatCompactWordCount(
                dialogueWordCount,
                languageCode: languageCode,
              ),
            },
          ),
        ),
      ],
    );
  }
}
