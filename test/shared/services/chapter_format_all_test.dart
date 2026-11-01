// 职责: 验证批量排版按候选 ID 读取最新正文、跳过无需改写的章节并正确报告进度。
// 关联文件:
//   lib/shared/services/chapter_format_all.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/database/novel_content_daos/chapter_dao.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/chapter_format_all.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  late NovelContentDatabase database;
  late NovelContentService service;

  setUp(() {
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = NovelContentService(database);
  });
  tearDown(() => database.close());

  Future<void> insert(
    String id,
    String content, {
    String type = nodeTypeChapter,
  }) => database.chapterDao.insert(
    ChaptersCompanion.insert(
      id: id,
      type: type,
      siblingOrder: 1,
      content: Value(content),
    ),
  );

  test('candidate IDs cover active chapter and extra bodies', () async {
    await insert('chapter', '第一段\n\n第二段');
    await insert('extra', '番外', type: nodeTypeExtra);
    await insert('formatted', '\u3000\u3000已排版');
    await insert('volume', '卷正文', type: nodeTypeVolume);
    await insert('empty', '');
    await insert('deleted', '已删除');
    await database.chapterDao.softDelete('deleted');

    expect(await service.getChapterIdsWithContent(), [
      'chapter',
      'extra',
      'formatted',
    ]);
    expect(await service.getChapterBodyById('chapter'), '第一段\n\n第二段');
  });

  test(
    'scan and execution respect formatting settings and English boundaries',
    () async {
      await insert('c1', '他说 hello   world 然后 离开');
      await insert('c2', '\u3000\u3000hello world');
      final ids = await service.getChapterIdsWithContent();
      expect(
        await formatAllChapterContents(
          contentService: service,
          chapterIds: ids,
          allowSpaces: false,
        ),
        1,
      );
      expect(
        await service.getChapterBodyById('c1'),
        '\u3000\u3000他说hello world然后离开',
      );
      expect(await service.getChapterBodyById('c2'), '\u3000\u3000hello world');
    },
  );

  test(
    'custom indent and paragraph spacing remain consistent across phases',
    () async {
      await insert('chapter', '\u3000第一段\n\u3000第二段');
      final ids = await service.getChapterIdsWithContent();
      await formatAllChapterContents(contentService: service, chapterIds: ids);
      expect(
        await service.getChapterBodyById('chapter'),
        '\u3000\u3000第一段\n\n\u3000\u3000第二段',
      );
    },
  );

  test(
    'execution reads current content without adding unconfirmed chapters',
    () async {
      await insert('chapter', '确认前正文');
      final ids = await service.getChapterIdsWithContent();
      await service.updateChapterContentPartial(
        chapterId: 'chapter',
        content: '确认后新正文',
      );
      await insert('new', '后来创建的章节');
      final progress = <(int, int)>[];
      expect(
        await formatAllChapterContents(
          contentService: service,
          chapterIds: ids,
          onProgress: (done, total) => progress.add((done, total)),
        ),
        1,
      );
      expect(await service.getChapterBodyById('chapter'), '\u3000\u3000确认后新正文');
      expect(await service.getChapterBodyById('new'), '后来创建的章节');
      expect(progress, [(1, 1)]);
    },
  );

  test(
    'already formatted targets skip writes but still advance progress',
    () async {
      await insert('a', '第一章');
      await insert('b', '第二章');
      final ids = await service.getChapterIdsWithContent();
      await service.updateFormattedChapterContent(
        chapterId: 'a',
        content: '\u3000\u3000第一章',
      );
      final before = (await service.getChapterById('a'))!.updatedAt;
      final progress = <(int, int)>[];
      expect(
        await formatAllChapterContents(
          contentService: service,
          chapterIds: ids,
          onProgress: (done, total) => progress.add((done, total)),
        ),
        1,
      );
      expect((await service.getChapterById('a'))!.updatedAt, before);
      expect(progress, [(1, 2), (2, 2)]);
    },
  );

  test(
    'chapters deleted after confirmation are skipped without aborting',
    () async {
      await insert('a', '第一章');
      await insert('b', '第二章');
      final ids = await service.getChapterIdsWithContent();
      await database.chapterDao.softDelete('a');
      final progress = <(int, int)>[];
      expect(
        await formatAllChapterContents(
          contentService: service,
          chapterIds: ids,
          onProgress: (done, total) => progress.add((done, total)),
        ),
        1,
      );
      expect(await service.getChapterBodyById('a'), null);
      expect(await service.getChapterBodyById('b'), '\u3000\u3000第二章');
      expect(progress, [(1, 2), (2, 2)]);
    },
  );

  test('empty candidates and execution do nothing', () async {
    expect(await service.getChapterIdsWithContent(), isEmpty);
    expect(
      await formatAllChapterContents(
        contentService: service,
        chapterIds: const [],
        onProgress: (_, _) => fail('No chapters to process'),
      ),
      0,
    );
  });
}
