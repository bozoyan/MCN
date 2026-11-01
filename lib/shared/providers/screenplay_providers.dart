// 职责: 装配剧本 Service 与按内容库参数化、自动释放的 Drift stream providers。
// 关联文件:
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/service-naming.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../models/screenplay.dart';
import '../models/screenplay_element.dart';
import '../services/screenplay_service.dart';
import 'novel_providers.dart';

part 'screenplay_providers.g.dart';

@riverpod
ScreenplayService screenplayService(
  Ref ref,
  String databasePath, {
  String? novelId,
}) {
  return ScreenplayService(
    ref.watch(novelContentDatabaseProvider(databasePath)),
    novelActionsService: novelId == null
        ? null
        : ref.watch(novelActionsProvider),
    novelId: novelId,
  );
}

@riverpod
Stream<ScreenplayRow?> screenplayRoot(Ref ref, String databasePath) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchRoot();
}

@riverpod
Stream<List<ScreenplaySeasonRow>> screenplaySeasons(
  Ref ref,
  String databasePath,
  String screenplayId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchSeasons(screenplayId);
}

@riverpod
Stream<List<ScreenplayEpisodeRow>> screenplayEpisodes(
  Ref ref,
  String databasePath,
  String seasonId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchEpisodes(seasonId);
}

/// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。
@riverpod
Stream<List<ScreenplayEpisodeRow>> screenplayEpisodesOfScreenplay(
  Ref ref,
  String databasePath,
  String screenplayId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchEpisodesOfScreenplay(screenplayId);
}

@riverpod
Stream<ScreenplayEpisodeRow?> screenplayEpisode(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchEpisode(episodeId);
}

@riverpod
Stream<List<ScreenplaySceneSummary>> screenplayScenes(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchScenes(episodeId);
}

/// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。
@riverpod
Stream<Map<String, List<ScreenplaySceneSummary>>> screenplayScenesOfScreenplay(
  Ref ref,
  String databasePath,
  String screenplayId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchScenesOfScreenplay(screenplayId);
}

@riverpod
Stream<List<ScreenplayOutlineEntry>> screenplayOutline(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchOutline(episodeId);
}

@riverpod
Stream<List<ScreenplayBeatSummary>> screenplayBeats(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchBeats(episodeId);
}

@riverpod
Stream<List<ScreenplayAppearanceMatrixRow>> screenplayAppearanceMatrix(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchAppearanceMatrix(episodeId);
}

@riverpod
Stream<List<ScreenplayElement>> screenplaySceneElements(
  Ref ref,
  String databasePath,
  String sceneId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchElements(sceneId);
}

@riverpod
Stream<ScreenplayOverview> screenplayOverview(
  Ref ref,
  String databasePath,
  String screenplayId, {
  String? seasonId,
}) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchOverview(screenplayId, seasonId: seasonId);
}

@riverpod
Stream<List<EpisodeScriptScenePreview>> screenplayEpisodeScriptPreview(
  Ref ref,
  String databasePath,
  String episodeId,
) {
  return ref
      .watch(novelContentDatabaseProvider(databasePath))
      .screenplayDao
      .watchEpisodeScriptPreview(episodeId);
}
