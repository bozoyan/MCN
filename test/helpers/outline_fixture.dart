// 职责: 在隔离测试库中严格插入保留历史 ID 的大纲 fixture。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/outline.dart
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/outline.dart';

Future<void> insertOutlineFixture(
  NovelContentDatabase database,
  OutlineDraft draft,
) async {
  await database.outlineDao.insertOutline(
    Outline(
      documentId: draft.documentId,
      title: draft.title,
      content: draft.content,
      status: draft.status,
      startChapterNum: draft.startChapterNum,
      sortOrder: draft.sortOrder,
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
      deletedAt: draft.deletedAt,
    ),
  );
  for (final (index, beat) in draft.beats.indexed) {
    await database.outlineDao.insertBeat(
      OutlineBeat(
        id: beat.id,
        outlineDocumentId: draft.documentId,
        title: beat.title,
        content: beat.content,
        status: beat.status,
        chapterCount: beat.chapterCount,
        sortOrder: index,
        createdAt: draft.createdAt,
        updatedAt: draft.updatedAt,
        deletedAt: notDeletedSentinel,
      ),
    );
  }
}
