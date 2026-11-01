// 职责: 验证章节连续保存使用最新持久化基线，不产生重复或跳版历史。
// 关联文件:
//   lib/shared/services/chapter_save.dart
//   lib/shared/services/working_overlay.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/chapter_save.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  late NovelContentDatabase database;
  late AppDatabase appDatabase;
  late NovelContentService contentService;
  late WorkingOverlayService overlay;

  setUp(() {
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDatabase = AppDatabase.forTest(NativeDatabase.memory());
    contentService = NovelContentService(database);
    overlay = WorkingOverlayService(
      database,
      contentService,
      novelActionsService: NovelActionsService(appDatabase),
    );
  });

  tearDown(() async {
    await database.close();
    await appDatabase.close();
  });

  test(
    'serial saves advance history baseline and skip duplicate snapshots',
    () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: 'Chapter 1',
      );
      await contentService.updateChapterContent(
        chapterId: chapterId,
        title: 'Chapter 1',
        outline: '',
        content: 'v0',
      );
      final staleChapter = await contentService.getChapterById(chapterId);
      expect(staleChapter, isNotNull);

      Future<bool> save(String content) {
        return commitChapterManualSave(
          overlay,
          contentService,
          chapterId: chapterId,
          newTitle: staleChapter!.title ?? '',
          newOutline: staleChapter.outline,
          newContent: content,
        );
      }

      expect(await save('v1'), isTrue);
      expect(await save('v2'), isTrue);

      final commits = await database.changeCommitDao.getAll();
      expect(commits, hasLength(1));
      var items = await database.changeCommitDao.getItemsByCommit(
        commits.single.id,
      );
      // 落库的 resourcePath 不带前导斜杠（写入路径规范化后统一去掉）。
      var contentItems = items
          .where((item) => item.resourcePath == 'chapters/$chapterId/content')
          .toList();
      expect(contentItems, hasLength(2));
      final secondSave = contentItems.singleWhere(
        (item) => item.newText == 'v2',
      );
      expect(secondSave.oldText, 'v1');

      expect(await save('v2'), isFalse);
      items = await database.changeCommitDao.getItemsByCommit(
        commits.single.id,
      );
      contentItems = items
          .where((item) => item.resourcePath == 'chapters/$chapterId/content')
          .toList();
      expect(contentItems, hasLength(2));
    },
  );
}
