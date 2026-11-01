// 职责: 阅读进度状态管理 — 按 novelId 持久化最近阅读章节与滚动位置，跨会话恢复。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/app_database.dart';
import 'novel_providers.dart';

part 'reading_progress_providers.g.dart';

/// 监听某本作品的阅读进度。
///
/// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
/// Reader 页面使用此 provider 作为唯一写入入口与读取入口。
@riverpod
class NovelReadingProgress extends _$NovelReadingProgress {
  @override
  Future<ReadingProgressData> build(String novelId) async {
    final db = ref.watch(appDatabaseProvider);
    final existing = await db.readingProgressDao.getByNovelId(novelId);
    if (existing != null) {
      return existing;
    }
    return ReadingProgressData(
      novelId: novelId,
      chapterId: null,
      scrollOffset: 0,
      lastReadAt: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 更新当前阅读章节，同时记录最后阅读时间。
  ///
  /// 切换章节时必须将 scrollOffset 重置为 0，否则上一章的滚动偏移会
  /// 被关联到新章节，导致下次打开时定位到错误位置甚至触发连续流
  /// 加载大量中间章节。
  Future<void> setChapterId(String chapterId) async {
    final now = DateTime.now();
    final current = state.value;
    final companion = ReadingProgressCompanion(
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      scrollOffset: const Value(0),
      lastReadAt: Value(now),
      updatedAt: Value(now),
    );
    final db = ref.read(appDatabaseProvider);
    await db.readingProgressDao.upsert(companion);
    // 直接用已知值更新 state，避免 upsert 后多一次 SELECT 查询。
    state = AsyncData(
      (current ?? _emptyData()).copyWith(
        chapterId: Value(chapterId),
        scrollOffset: 0,
        lastReadAt: Value(now),
        updatedAt: now,
      ),
    );
  }

  /// 原子更新连续阅读的章节与章内滚动偏移。
  ///
  /// 连续阅读的 [scrollOffset] 始终相对于 [chapterId] 的章节顶部，不能
  /// 使用跨章节的列表绝对坐标，否则恢复时会错误跳过大量章节。
  Future<void> setChapterProgress({
    required String chapterId,
    required double scrollOffset,
  }) async {
    final current = state.value;
    if (current != null &&
        current.chapterId == chapterId &&
        (current.scrollOffset - scrollOffset).abs() < 1) {
      return;
    }
    final now = DateTime.now();
    final companion = ReadingProgressCompanion(
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      scrollOffset: Value(scrollOffset),
      lastReadAt: Value(now),
      updatedAt: Value(now),
    );
    final db = ref.read(appDatabaseProvider);
    await db.readingProgressDao.upsert(companion);
    state = AsyncData(
      (current ?? _emptyData()).copyWith(
        chapterId: Value(chapterId),
        scrollOffset: scrollOffset,
        lastReadAt: Value(now),
        updatedAt: now,
      ),
    );
  }

  /// 更新滚动偏移（单章滚动 / 水平翻页页码 / 连续滚动偏移通用）。
  Future<void> setScrollOffset(double offset) async {
    final current = state.value;
    if (current != null && (current.scrollOffset - offset).abs() < 1) {
      return;
    }
    final now = DateTime.now();
    final companion = ReadingProgressCompanion(
      novelId: Value(novelId),
      scrollOffset: Value(offset),
      updatedAt: Value(now),
    );
    final db = ref.read(appDatabaseProvider);
    await db.readingProgressDao.upsert(companion);
    state = AsyncData(
      (current ?? _emptyData()).copyWith(scrollOffset: offset, updatedAt: now),
    );
  }

  ReadingProgressData _emptyData() => ReadingProgressData(
    novelId: novelId,
    chapterId: null,
    scrollOffset: 0,
    lastReadAt: null,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  /// 清除该作品进度。
  Future<void> reset() async {
    final db = ref.read(appDatabaseProvider);
    await db.readingProgressDao.deleteByNovelId(novelId);
    state = AsyncData(
      ReadingProgressData(
        novelId: novelId,
        chapterId: null,
        scrollOffset: 0,
        lastReadAt: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }
}
