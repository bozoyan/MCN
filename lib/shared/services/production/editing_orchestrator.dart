// 职责: 在作品事务中为尚未关联剪辑的剧集创建空工程，校验已有引用且不替换失效引用。
// 关联文件:
//   lib/shared/database/novel_content_daos/editing_dao.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/editing/document.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../database/novel_content_database.dart';
import '../../logger/app_logger.dart';
import '../../models/editing/document.dart';
import '../../models/screenplay.dart';

final _log = AppLogger.forModule('EpisodeEditing');

class EpisodeEditingOrchestrator {
  Future<({VideoEditingRow editing, bool created})> ensureEpisodeEditing(
    NovelContentDatabase db,
    String episodeId,
  ) async {
    try {
      return await db.transaction(() async {
        final episode = await db.screenplayDao.getEpisode(episodeId);
        if (episode == null) {
          throw const ScreenplayServiceException(
            'episode_not_found',
            'Episode does not exist.',
          );
        }
        final existingId = episode.editingId;
        if (existingId != null) {
          final existing = await db.editingDao.get(existingId);
          if (existing == null) {
            throw const ScreenplayServiceException(
              'editing_not_found',
              'The linked editing does not exist.',
            );
          }
          return (editing: existing, created: false);
        }
        final screenplay = await db.screenplayDao.getRoot();
        if (screenplay == null || screenplay.id != episode.screenplayId) {
          throw const ScreenplayServiceException(
            'screenplay_not_found',
            'Screenplay does not exist.',
          );
        }
        final id = const Uuid().v4();
        await db.editingDao.create(
          id,
          episode.title.trim().isEmpty
              ? '${episode.episodeNumber}'
              : episode.title,
          EditingDocument.empty(screenplay.ratio),
        );
        await (db.update(
          db.screenplayEpisodes,
        )..where((t) => t.id.equals(episodeId))).write(
          ScreenplayEpisodesCompanion(
            editingId: Value(id),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return (editing: (await db.editingDao.get(id))!, created: true);
      });
    } catch (error, stack) {
      _log.error(
        '[DB] table=video_editings,screenplay_episodes op=INSERT,UPDATE id=$episodeId',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
