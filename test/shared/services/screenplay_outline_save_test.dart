// 职责: 验证集大纲手动保存进历史，并接管同一集上待审阅的 AI 改动。
// 关联文件:
//   lib/shared/services/screenplay_outline_save.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/services/screenplay_service.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_outline_save.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  late NovelContentDatabase database;
  late AppDatabase appDatabase;
  late WorkingOverlayService overlay;
  late ScreenplayService screenplayService;
  late String episodeId;
  late String outlinePath;

  setUp(() async {
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDatabase = AppDatabase.forTest(NativeDatabase.memory());
    overlay = WorkingOverlayService(
      database,
      NovelContentService(database),
      novelActionsService: NovelActionsService(appDatabase),
    );
    screenplayService = ScreenplayService(database);
    final initial = await screenplayService.createInitialStructure();
    episodeId = initial.episodeId;
    outlinePath = '/episodes/$episodeId/outline';
  });

  tearDown(() async {
    await database.close();
    await appDatabase.close();
  });

  Future<String> currentOutline() async {
    return (await database.screenplayDao.getEpisode(episodeId))!.outline;
  }

  test('serial saves use the persisted baseline and skip no-ops', () async {
    expect(
      await commitEpisodeOutlineManualSave(
        overlay,
        database,
        episodeId: episodeId,
        newOutline: '第一版',
      ),
      isTrue,
    );
    // 列写入由 apply-on-stage 完成，调用方不再单独写库。
    expect(await currentOutline(), '第一版');

    expect(
      await commitEpisodeOutlineManualSave(
        overlay,
        database,
        episodeId: episodeId,
        newOutline: '第二版',
      ),
      isTrue,
    );
    expect(await currentOutline(), '第二版');

    // 基线现读：第二次的 oldText 必须是「第一版」，不是初始空串。
    final items = await overlay.getChangeCommitItemsForResource(outlinePath);
    expect(items.map((item) => item.newText), containsAll(['第一版', '第二版']));
    expect(items.any((item) => item.oldText == '第一版'), isTrue);

    // 无变化不提交。
    expect(
      await commitEpisodeOutlineManualSave(
        overlay,
        database,
        episodeId: episodeId,
        newOutline: '第二版',
      ),
      isFalse,
    );
  });

  test('missing episode is a no-op', () async {
    expect(
      await commitEpisodeOutlineManualSave(
        overlay,
        database,
        episodeId: 'episode_missing',
        newOutline: '随便',
      ),
      isFalse,
    );
  });

  test(
    'manual save takes over a pending AI change instead of orphaning it',
    () async {
      await screenplayService.updateEpisodeOutline(
        episodeId: episodeId,
        outline: '原大纲',
      );
      final aiChange = await overlay.stageTextChange(
        resourcePath: outlinePath,
        resourceType: workingChangeResourceTypeScreenplayEpisodes,
        resourceId: episodeId,
        field: 'outline',
        oldText: '原大纲',
        newText: 'AI 大纲',
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
        expectedCurrentText: '原大纲',
      );

      expect(
        await commitEpisodeOutlineManualSave(
          overlay,
          database,
          episodeId: episodeId,
          newOutline: '用户接着改的大纲',
        ),
        isTrue,
      );

      // AI 那条被提交，而不是留成 oldText 已失真的孤儿 active。
      expect(
        (await database.workingChangeDao.getById(aiChange.id))?.status,
        workingChangeStatusCommitted,
      );
      expect(
        (await overlay.getWorkingChanges()).where(
          (change) => change.status == workingChangeStatusActive,
        ),
        isEmpty,
      );
      final items = await overlay.getChangeCommitItemsForResource(outlinePath);
      expect(
        items.map((item) => (item.oldText, item.newText)),
        unorderedEquals([('原大纲', 'AI 大纲'), ('AI 大纲', '用户接着改的大纲')]),
      );
      expect(await currentOutline(), '用户接着改的大纲');

      // 主动回退恢复该条历史目标，覆盖之后的手工内容。
      expect(
        await overlay.rollbackChange(aiChange.id),
        RollbackChangeResult.rolledBack,
      );
      expect(await currentOutline(), '原大纲');
    },
  );

  test('manual save leaves another episode AI change pending', () async {
    final episode = (await database.screenplayDao.getEpisode(episodeId))!;
    final otherId = await screenplayService.createEpisode(
      seasonId: episode.seasonId,
    );
    final otherChange = await overlay.stageTextChange(
      resourcePath: '/episodes/$otherId/outline',
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: otherId,
      field: 'outline',
      oldText: '',
      newText: '另一集 AI 大纲',
      source: workingChangeSourceAi,
      sourceSessionId: 'other_session',
    );
    await overlay.stageTextChange(
      resourcePath: outlinePath,
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: episodeId,
      field: 'outline',
      oldText: '',
      newText: 'AI 大纲',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
    );
    await commitEpisodeOutlineManualSave(
      overlay,
      database,
      episodeId: episodeId,
      newOutline: '用户大纲',
    );
    expect(await currentOutline(), '用户大纲');
    expect(
      (await database.workingChangeDao.getById(otherChange.id))?.status,
      workingChangeStatusActive,
    );
    expect(
      (await database.screenplayDao.getEpisode(otherId))!.outline,
      '另一集 AI 大纲',
    );
    expect(
      await overlay.getChangeCommitItemsForResource(
        '/episodes/$otherId/outline',
      ),
      isEmpty,
    );
  });

  test(
    'failed manual commit rolls back AI takeover and outline write',
    () async {
      final aiChange = await overlay.stageTextChange(
        resourcePath: outlinePath,
        resourceType: workingChangeResourceTypeScreenplayEpisodes,
        resourceId: episodeId,
        field: 'outline',
        oldText: '',
        newText: 'AI 大纲',
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
      );
      await database.customStatement("""
CREATE TRIGGER fail_manual_outline_commit BEFORE INSERT ON change_commits
WHEN NEW.source = '$workingChangeSourceManual'
BEGIN
  SELECT RAISE(ABORT, 'injected manual outline commit failure');
END
""");
      await expectLater(
        commitEpisodeOutlineManualSave(
          overlay,
          database,
          episodeId: episodeId,
          newOutline: '用户大纲',
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'injected manual outline commit failure',
            ),
          ),
        ),
      );
      expect(await currentOutline(), 'AI 大纲');
      expect(
        (await database.workingChangeDao.getById(aiChange.id))?.status,
        workingChangeStatusActive,
      );
      expect(await overlay.getChangeCommits(), isEmpty);
      expect(
        await overlay.getChangeCommitItemsForResource(outlinePath),
        isEmpty,
      );
      expect((await overlay.getWorkingChanges()).map((change) => change.id), [
        aiChange.id,
      ]);
    },
  );
}
