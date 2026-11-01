// 职责: NovelListX 书架可见、首页 featured、排序与分类筛选规则测试 — 保证桌面/移动端复用同一过滤语义。
// 关联文件:
//   lib/shared/models/novel.dart
//   lib/shared/database/app_database.dart
//   lib/shared/models/content_status.dart
//   lib/shared/models/novel_type.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel.dart';
import 'package:reveric/shared/models/novel_type.dart';

Novel _novel({
  required String id,
  required DateTime updatedAt,
  bool draft = false,
  DateTime? deletedAt,
  DateTime? createdAt,
  String? title,
  int wordCount = 0,
  String category = '',
}) {
  return Novel(
    id: id,
    title: title ?? id,
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindNovel,
    wordCount: wordCount,
    draft: draft,
    category: category,
    tags: const [],
    createdAt: createdAt ?? updatedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt ?? notDeletedSentinel,
  );
}

void main() {
  group('NovelListX.shelfVisible / continue writing', () {
    // 首页 hero 与书库列表依赖此过滤：draft / 软删作品绝不能进书架展示。
    test('shelfVisible excludes draft and soft-deleted novels', () {
      final now = DateTime(2026, 7, 23);
      final novels = [
        _novel(id: 'kept', updatedAt: now),
        _novel(
          id: 'draft',
          updatedAt: now.add(const Duration(days: 1)),
          draft: true,
        ),
        _novel(
          id: 'deleted',
          updatedAt: now.add(const Duration(days: 2)),
          deletedAt: now,
        ),
      ];

      expect(novels.shelfVisible.map((n) => n.id), ['kept']);
    });

    // 继续写必须与 shelfVisible 同源；否则会出现「书库没有、继续写却有」的分叉。
    test(
      'continue writing picks most recently updated shelf-visible novel',
      () {
        final older = DateTime(2026, 7, 20);
        final newer = DateTime(2026, 7, 23);
        final novels = [
          _novel(id: 'older', updatedAt: older),
          _novel(
            id: 'draft-newer',
            updatedAt: newer.add(const Duration(days: 1)),
            draft: true,
          ),
          _novel(id: 'newer', updatedAt: newer),
        ];

        expect(
          novels.shelfVisible.sortedForShelf(LibrarySortOrder.updated).first.id,
          'newer',
        );
      },
    );

    test('drafts returns undeleted draft novels only', () {
      final now = DateTime(2026, 7, 23);
      final novels = [
        _novel(id: 'kept', updatedAt: now),
        _novel(
          id: 'draft',
          updatedAt: now.add(const Duration(days: 1)),
          draft: true,
        ),
        _novel(
          id: 'deleted-draft',
          updatedAt: now.add(const Duration(days: 2)),
          draft: true,
          deletedAt: now,
        ),
      ];

      expect(novels.drafts.map((n) => n.id), ['draft']);
    });
  });

  group('NovelListX.sortedForShelf', () {
    final base = DateTime(2026, 9, 1);
    final novels = [
      _novel(
        id: 'a',
        title: 'B 书',
        updatedAt: base.add(const Duration(days: 3)),
        createdAt: base,
        wordCount: 100,
      ),
      _novel(
        id: 'b',
        title: 'A 书',
        updatedAt: base.add(const Duration(days: 1)),
        createdAt: base.add(const Duration(days: 2)),
        wordCount: 5000,
      ),
      _novel(
        id: 'c',
        title: 'C 书',
        updatedAt: base.add(const Duration(days: 2)),
        createdAt: base.add(const Duration(days: 1)),
        wordCount: 100,
      ),
    ];

    test('each order sorts as labelled and ties fall back to updatedAt', () {
      List<String> ids(LibrarySortOrder o) =>
          novels.sortedForShelf(o).map((n) => n.id).toList();
      expect(ids(LibrarySortOrder.updated), ['a', 'c', 'b']);
      expect(ids(LibrarySortOrder.created), ['b', 'c', 'a']);
      expect(ids(LibrarySortOrder.title), ['b', 'a', 'c']);
      expect(ids(LibrarySortOrder.wordCount), ['b', 'a', 'c']);
    });

    test('does not mutate the source list', () {
      novels.sortedForShelf(LibrarySortOrder.title);
      expect(novels.map((n) => n.id), ['a', 'b', 'c']);
    });
  });

  group('NovelListX category filtering', () {
    final now = DateTime(2026, 9, 1);
    final novels = [
      _novel(id: 'a', updatedAt: now, category: '玄幻'),
      _novel(id: 'b', updatedAt: now, category: ' 玄幻 '),
      _novel(id: 'c', updatedAt: now, category: '都市'),
      _novel(id: 'd', updatedAt: now),
    ];

    test('categoryCounts trims values, keeps uncategorized under empty key '
        'and orders by count', () {
      expect(novels.categoryCounts, {'玄幻': 2, '': 1, '都市': 1});
      expect(novels.categoryCounts.keys.toList(), ['玄幻', '', '都市']);
    });

    test('whereCategory: null keeps all, empty matches uncategorized', () {
      expect(novels.whereCategory(null).length, 4);
      expect(novels.whereCategory('玄幻').map((n) => n.id), ['a', 'b']);
      expect(novels.whereCategory('').map((n) => n.id), ['d']);
    });
  });
}
