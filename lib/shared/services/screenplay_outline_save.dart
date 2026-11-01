// 职责: 集大纲手动保存的修改历史写入 — stage 变更并提交 manual commit，供桌面与移动端复用。
// 关联文件:
//   lib/shared/services/working_overlay.dart
//   lib/shared/services/screenplay_service.dart
//   lib/desktop/features/screenplay/outline.dart
//   lib/mobile/features/screenplay/outline_page.dart
//   assets/translations/en/history.json
//   assets/translations/zh-CN/history.json
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../utils/resource_path.dart';
import 'working_overlay.dart';

final _log = AppLogger.forModule('ScreenplayOutlineSave');

/// 集大纲手动保存的 manual commit 消息 key。
const String screenplayOutlineManualSaveMessage =
    'history.commit_message.manual_episode_outline_save';

/// 在同一事务内读取最新大纲，先提交当前集的待审阅 AI 改动，再保存用户版本。
///
/// 接管必须在 stage 手动变更之前完成，否则 AI 会话锁会阻止手动写入。
/// 基线现读避免连续保存复用旧快照；任一步失败都会回滚内容、AI 接管和手动历史。
///
/// 真正的列写入由 overlay 的 apply-on-stage 完成，调用方不要再调
/// `ScreenplayService.updateEpisodeOutline`，否则会绕开历史。
///
/// 返回是否有变化（即是否产生了 commit）。
Future<bool> commitEpisodeOutlineManualSave(
  WorkingOverlayService overlay,
  NovelContentDatabase database, {
  required String episodeId,
  required String newOutline,
}) async {
  try {
    return await database.transaction(() async {
      final before = await database.screenplayDao.getEpisode(episodeId);
      if (before == null || before.outline == newOutline) {
        return false;
      }
      final scope = 'episodes/$episodeId';
      final aiChangeIds = (await overlay.getWorkingChanges())
          .where(
            (change) =>
                change.status == workingChangeStatusActive &&
                change.source == workingChangeSourceAi &&
                resourcePathIsWithin(change.resourcePath, scope),
          )
          .map((change) => change.id)
          .toList();
      await overlay.commitWorkingChanges(
        aiChangeIds,
        source: workingChangeSourceAi,
        message: 'history.commit_message.auto_commit_ai_changes',
      );
      final change = await overlay.stageTextChange(
        resourcePath: '$scope/outline',
        resourceType: workingChangeResourceTypeScreenplayEpisodes,
        resourceId: episodeId,
        field: 'outline',
        oldText: before.outline,
        newText: newOutline,
        source: workingChangeSourceManual,
        summary: 'Update screenplay episode outline',
      );
      await overlay.commitManualSave(
        manualChangeIds: [change.id],
        resourceScopes: [scope],
        manualMessage: screenplayOutlineManualSaveMessage,
      );
      return true;
    });
  } catch (error, stackTrace) {
    _log.error(
      '[DB] table=screenplay_episodes,working_changes,change_commits,change_commit_items '
      'operation=UPDATE/INSERT id=$episodeId',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}
