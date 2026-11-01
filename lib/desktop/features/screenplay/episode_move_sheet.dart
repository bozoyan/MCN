// 职责: 桌面分集跨季移动弹窗 — 选择目标季并调用稳定 ID 的跨季移动事务。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/desktop/features/screenplay/context_panel.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import '../../../shared/theme/theme.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/screenplay_service.dart';
import 'support.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';

Future<void> showScreenplayEpisodeMoveSheet(
  BuildContext context, {
  required ScreenplayService service,
  required ScreenplayEpisodeRow episode,
  required List<ScreenplayEpisodeRow> currentSeasonEpisodes,
  required List<ScreenplaySeasonRow> seasons,
  required Future<void> Function(String seasonId) onMoved,
}) async {
  if (currentSeasonEpisodes.length == 1) return;
  final targetSeasonId = await showRevericDialog<String>(
    context: context,
    builder: (dialogContext) => RevericDialog.panel(
      title: Text(context.t(LocaleKeys.screenplayEpisodeMove)),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final season in seasons)
              if (season.id != episode.seasonId)
                ListTile(
                  title: Text(screenplaySeasonLabel(context, season)),
                  onTap: () => Navigator.of(dialogContext).pop(season.id),
                ),
          ],
        ),
      ),

      width: 360 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
  if (targetSeasonId == null) return;
  await service.updateEpisode(
    episodeId: episode.id,
    targetSeasonId: targetSeasonId,
  );
  await onMoved(targetSeasonId);
}
