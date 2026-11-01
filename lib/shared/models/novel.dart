// 职责: Novel 模型导出与列表过滤扩展（书架可见、排序与类型可用的排序项；表单字段在 novel_form_fields.dart）
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/novel_form_fields.dart
//   lib/desktop/widgets/home/library_home_panel.dart
//   lib/mobile/pages/library_page.dart
//   lib/shared/widgets/novel/library_shelf_labels.dart

import 'content_kind.dart';
import '../database/app_database.dart';

export '../database/app_database.dart' show Novel, Novels, NovelsCompanion;

extension NovelX on Novel {
  bool get isEmpty => title.trim().isEmpty;

  bool get hasDescription => description.trim().isNotEmpty;

  bool get hasContentDatabase =>
      contentDatabasePath != null && contentDatabasePath!.isNotEmpty;

  String get statusDisplay {
    switch (status) {
      case 'in_progress':
        return '进行中';
      case 'completed':
        return '已完成';
      case 'hiatus':
        return '暂停';
      case 'abandoned':
        return '已弃坑';
      default:
        return status;
    }
  }
}

extension NovelListX on List<Novel> {
  List<Novel> get active =>
      where((n) => n.deletedAt == notDeletedSentinel).toList();

  /// 过滤掉尚未「加入书架」的快速开书草稿（draft 仍为 true）。
  List<Novel> get visibleInLibrary => where((n) => !n.draft).toList();

  /// 未删除的快速开书草稿（尚未加入书架）。
  List<Novel> get drafts => active.where((n) => n.draft).toList();

  /// 书架/书库展示集合：未删除且已加入书架。
  /// 桌面首页、移动端首页 hero、两端书库列表统一走这里，避免各自拼 filter。
  List<Novel> get shelfVisible => active.visibleInLibrary;

  /// 按 [order] 排出的新列表；时间与字数都是新/多的在前，书名按字典序。
  List<Novel> sortedForShelf(LibrarySortOrder order) {
    final sorted = [...this];
    int byUpdated(Novel a, Novel b) => b.updatedAt.compareTo(a.updatedAt);
    sorted.sort(switch (order) {
      LibrarySortOrder.updated => byUpdated,
      LibrarySortOrder.created => (a, b) => b.createdAt.compareTo(a.createdAt),
      LibrarySortOrder.title => (a, b) {
        final c = a.title.trim().compareTo(b.title.trim());
        return c != 0 ? c : byUpdated(a, b);
      },
      LibrarySortOrder.wordCount => (a, b) {
        final c = b.wordCount.compareTo(a.wordCount);
        return c != 0 ? c : byUpdated(a, b);
      },
    });
    return sorted;
  }

  /// [category] 为 null 不过滤；空串匹配未分类作品。
  List<Novel> whereCategory(String? category) {
    if (category == null) return this;
    return where((n) => n.category.trim() == category).toList();
  }

  /// 分类 → 作品数，按数量降序、同数按名称；未分类记在空串下。
  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final n in this) {
      final key = n.category.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return {for (final k in keys) k: counts[k]!};
  }
}

enum LibrarySortOrder { updated, created, title, wordCount }

/// 字数只是小说的口径；混排或只看剧本时不给这个排序。[contentKind] 为 null 表示混排。
List<LibrarySortOrder> librarySortOrdersFor(String? contentKind) => [
  for (final order in LibrarySortOrder.values)
    if (order != LibrarySortOrder.wordCount || contentKind == contentKindNovel)
      order,
];
