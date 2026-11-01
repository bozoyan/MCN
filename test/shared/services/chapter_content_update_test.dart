// 职责: 验证普通章节保存的原表读取及批量排版保留字数、不更新小说记录。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/services/chapter_format_all.dart
//   lib/shared/database/novel_content_daos/chapter_dao.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/chapter_format_all.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  late NovelContentDatabase database;
  late NovelContentService service;
  late _ReadRecorder reads;

  setUp(() async {
    reads = _ReadRecorder();
    database = NovelContentDatabase.forTest(
      NativeDatabase.memory().interceptWith(reads),
    );
    service = NovelContentService(database);
    await database.chapterDao.insert(
      ChaptersCompanion.insert(
        id: 'chapter',
        type: nodeTypeChapter,
        siblingOrder: 1,
        title: const Value('标题'),
        outline: const Value('大纲'),
        brief: const Value('摘要'),
        content: const Value('旧正文'),
        wordCount: const Value(3),
        updatedAt: Value(DateTime.utc(2020)),
        embeddingSyncStatus: const Value('synced'),
        embeddingSyncModelId: const Value('model'),
      ),
    );
    reads.statements.clear();
  });

  tearDown(() => database.close());

  test('partial save reads once without computing chapter numbers', () async {
    await service.updateChapterContentPartial(
      chapterId: 'chapter',
      content: '新正文\n\n',
    );
    expect(reads.statements, hasLength(1));
    expect(reads.statements.single, contains('FROM chapter_nodes'));
    final saved = (await service.getChapterById('chapter'))!;
    expect(saved.content, '新正文\n\n');
    expect(saved.title, '标题');
    expect(saved.outline, '大纲');
    expect(saved.brief, '摘要');
    expect(saved.wordCount, 3);
    expect(saved.embeddingSyncStatus, chapterEmbeddingSyncStatusPending);
    expect(saved.chapterNum, 1);
  });

  test(
    'full save reads the raw baseline and preserves unchanged embedding',
    () async {
      await service.updateChapterContent(
        chapterId: 'chapter',
        title: '标题',
        outline: '大纲',
        content: '旧正文',
      );
      expect(reads.statements, hasLength(1));
      expect(reads.statements.single, contains('FROM chapter_nodes'));
      final saved = (await service.getChapterById('chapter'))!;
      expect(saved.embeddingSyncStatus, 'synced');
      expect(saved.embeddingSyncModelId, 'model');
      expect(saved.brief, '摘要');
    },
  );

  test('partial metadata save keeps content and embedding state', () async {
    await service.updateChapterContentPartial(
      chapterId: 'chapter',
      brief: '新摘要',
    );
    final saved = (await service.getChapterById('chapter'))!;
    expect(saved.content, '旧正文');
    expect(saved.brief, '新摘要');
    expect(saved.embeddingSyncStatus, 'synced');
  });

  test(
    'batch formatting keeps counts and never accesses novel metadata',
    () async {
      final formattingService = NovelContentService(
        database,
        novelActionsService: _UnusedNovelActions(),
      );
      final chapterIds = await formattingService.getChapterIdsWithContent();
      expect(
        await formatAllChapterContents(
          contentService: formattingService,
          chapterIds: chapterIds,
        ),
        1,
      );
      final saved = (await service.getChapterById('chapter'))!;
      expect(saved.content, '\u3000\u3000旧正文');
      expect(saved.wordCount, 3);
      expect(saved.title, '标题');
      expect(saved.outline, '大纲');
      expect(saved.brief, '摘要');
      expect(saved.updatedAt.isAfter(DateTime.utc(2020)), isTrue);
      expect(saved.embeddingSyncStatus, chapterEmbeddingSyncStatusPending);
      expect(
        await formatAllChapterContents(
          contentService: formattingService,
          chapterIds: chapterIds,
        ),
        0,
      );
    },
  );

  test('missing and soft-deleted chapters cannot be saved', () async {
    await database.chapterDao.softDelete('chapter');
    for (final id in ['chapter', 'missing']) {
      await expectLater(
        service.updateFormattedChapterContent(
          chapterId: id,
          content: 'changed',
        ),
        throwsStateError,
      );
      await expectLater(
        service.updateChapterContentPartial(chapterId: id, content: 'changed'),
        throwsException,
      );
      await expectLater(
        service.updateChapterContent(
          chapterId: id,
          title: '',
          outline: '',
          content: 'changed',
        ),
        throwsException,
      );
    }
    final row = await (database.select(
      database.chapters,
    )..where((t) => t.id.equals('chapter'))).getSingle();
    expect(row.content, '旧正文');
  });

  test('563 chapter formatting avoids per-chapter view scans', () async {
    for (var i = 1; i < 563; i++) {
      await database.chapterDao.insert(
        ChaptersCompanion.insert(
          id: 'chapter_$i',
          type: nodeTypeChapter,
          siblingOrder: i + 1,
          content: Value('测试正文。' * 200),
        ),
      );
    }
    reads.statements.clear();
    reads.elapsedMicros = 0;
    reads.maxBodyRows = 0;
    final stopwatch = Stopwatch()..start();
    final chapterIds = await service.getChapterIdsWithContent();
    final changed = await formatAllChapterContents(
      contentService: service,
      chapterIds: chapterIds,
    );
    stopwatch.stop();
    final viewReads = reads.statements
        .where((sql) => sql.contains('FROM chapters '))
        .length;
    debugPrint(
      'format 563: ${stopwatch.elapsedMilliseconds} ms; '
      'selects=${reads.statements.length}; viewReads=$viewReads; '
      'maxBodyRows=${reads.maxBodyRows}; '
      'selectTime=${reads.elapsedMicros ~/ 1000} ms',
    );
    expect(changed, 563);
    expect(reads.maxBodyRows, 1);
    expect(viewReads, 0);
    expect(
      await formatAllChapterContents(
        contentService: service,
        chapterIds: chapterIds,
      ),
      0,
    );
  });
}

class _UnusedNovelActions implements NovelActionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Formatting must not access novel metadata');
}

class _ReadRecorder extends QueryInterceptor {
  final statements = <String>[];
  var elapsedMicros = 0;
  var maxBodyRows = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    statements.add(statement);
    final stopwatch = Stopwatch()..start();
    try {
      final rows = await executor.runSelect(statement, args);
      final bodyRows = rows.where((row) => row['content'] is String).length;
      if (bodyRows > maxBodyRows) {
        maxBodyRows = bodyRows;
      }
      return rows;
    } finally {
      elapsedMicros += stopwatch.elapsedMicroseconds;
    }
  }
}
