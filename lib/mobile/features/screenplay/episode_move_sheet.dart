// 职责: 移动端分集跨季移动 Sheet — 选择目标季并跟随移动后的当前集。
// 关联文件:
//   lib/mobile/features/screenplay/episode_picker_sheet.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart'
    show ScreenplayEpisodeRow, ScreenplaySeasonRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/theme/theme.dart';
import 'support.dart';

Future<void> showMobileScreenplayEpisodeMoveSheet(
  BuildContext context, {
  required Novel novel,
  required ScreenplayEpisodeRow episode,
  required List<ScreenplaySeasonRow> seasons,
  required List<ScreenplayEpisodeRow> sourceEpisodes,
  required Future<bool> Function() onFlush,
}) async {
  if (sourceEpisodes.length == 1 || !await onFlush() || !context.mounted) {
    return;
  }
  final target = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(title: Text(context.t(LocaleKeys.screenplayEpisodeMove))),
        for (final season in seasons)
          if (season.id != episode.seasonId)
            ListTile(
              minTileHeight: 52,
              leading: const RevericIcon(
                RevericIcons.circle_outlined,
                size: 20,
              ),
              title: Text(mobileSeasonLabel(context, season)),
              onTap: () => Navigator.of(sheetContext).pop(season.id),
            ),
      ],
    ),
  );
  if (target == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context);
  final path = novel.contentDatabasePath!;
  final service = container.read(
    screenplayServiceProvider(path, novelId: novel.id),
  );
  await service.updateEpisode(episodeId: episode.id, targetSeasonId: target);
  final provider = screenplayWorkspaceStateControllerProvider(novel.id, path);
  final workspace = container.read(provider);
  container
      .read(provider.notifier)
      .update(
        workspace.copyWith(
          seasonId: target,
          episodeId: episode.id,
          clearSceneId: true,
        ),
      );
  if (context.mounted && Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}
