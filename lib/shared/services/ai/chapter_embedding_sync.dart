// 职责: 章节 embedding 后台同步队列，只处理章节 summary/content 的增量索引。
// 关联文件:
//   lib/shared/services/ai/chat.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/providers/ai_providers.dart
import 'dart:async';

import '../../database/novel_content_database.dart';
import '../../logger/app_logger.dart';
import '../novel_content.dart';

final _log = AppLogger.forModule('EmbeddingSync');

class ChapterEmbeddingSyncQueue {
  ChapterEmbeddingSyncQueue({
    required this._contentService,
    required String? embeddingModel,
  }) : _embeddingModel = (() {
         final t = embeddingModel?.trim();
         return (t == null || t.isEmpty) ? null : t;
       })();

  final NovelContentService _contentService;
  final String? _embeddingModel;
  final Set<String> _pendingChapterIds = <String>{};
  final Set<String> _inProgressChapterIds = <String>{};
  bool _isRunning = false;
  bool _isPaused = false;
  bool _disposed = false;
  Completer<void>? _pauseCompleter;

  bool get isPaused => _isPaused;
  bool get isIdle => !_isRunning && !_isPaused;

  void dispose() {
    _disposed = true;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  void setPaused(bool paused) {
    _isPaused = paused;
    if (paused && _pauseCompleter == null) {
      _pauseCompleter = Completer<void>();
    } else if (!paused) {
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
  }

  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _pauseCompleter = Completer<void>();
    unawaited(
      _contentService.upsertNovelState(
        key: novelStateKeyEmbeddingSync,
        status: novelStateStatusPaused,
      ),
    );
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    unawaited(
      _contentService.upsertNovelState(
        key: novelStateKeyEmbeddingSync,
        status: novelStateStatusRunning,
      ),
    );
    unawaited(drainPending());
  }

  Future<bool> enqueue(String chapterId) async {
    if (chapterId.trim().isEmpty) {
      return false;
    }
    if (_inProgressChapterIds.contains(chapterId)) {
      if (_log.isDebugEnabled) {
        _log.debug(
          'enqueue skipped for chapter $chapterId — already being synced',
        );
      }
      return false;
    }
    if (_embeddingModel == null) {
      if (_log.isDebugEnabled) {
        _log.debug(
          'enqueue skipped for chapter $chapterId — embeddingModel is null',
        );
      }
      return false;
    }
    _pendingChapterIds.add(chapterId);
    await _contentService.updateChapterEmbeddingSyncStatus(
      chapterId: chapterId,
      status: chapterEmbeddingSyncStatusPending,
    );
    unawaited(_drain());
    return true;
  }

  Future<void> drainPending() async {
    _log.debug('drainPending: scanning for pending chapters');
    final chapters = await _contentService.getChapters();
    for (final chapter in chapters) {
      if (chapter.embeddingSyncStatus == chapterEmbeddingSyncStatusPending ||
          chapter.embeddingSyncStatus == chapterEmbeddingSyncStatusSyncing) {
        _pendingChapterIds.add(chapter.id);
      }
    }
    if (_log.isDebugEnabled) {
      _log.debug(
        'drainPending: found ${_pendingChapterIds.length} pending chapters',
      );
    }
    if (_pendingChapterIds.isNotEmpty) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    if (_isRunning || _disposed) {
      return;
    }
    _isRunning = true;
    unawaited(
      _contentService.upsertNovelState(
        key: novelStateKeyEmbeddingSync,
        status: novelStateStatusRunning,
      ),
    );
    try {
      while (_pendingChapterIds.isNotEmpty) {
        if (_disposed) return;
        if (_isPaused) {
          _log.debug('_drain: paused, waiting for resume');
          await _pauseCompleter!.future;
          _log.debug('_drain: resumed');
        }
        if (_disposed) return;
        if (_pendingChapterIds.isEmpty) break;
        final chapterId = _pendingChapterIds.first;
        _pendingChapterIds.remove(chapterId);
        _inProgressChapterIds.add(chapterId);
        try {
          await _syncChapter(chapterId);
        } catch (e) {
          _log.error('_drain: _syncChapter crashed for chapter $chapterId: $e');
          await _contentService.updateChapterEmbeddingSyncStatus(
            chapterId: chapterId,
            status: chapterEmbeddingSyncStatusError,
          );
        }
        _inProgressChapterIds.remove(chapterId);
      }
    } finally {
      _isRunning = false;
      if (!_disposed) {
        unawaited(
          _contentService.upsertNovelState(
            key: novelStateKeyEmbeddingSync,
            status: novelStateStatusIdle,
          ),
        );
      }
    }
  }

  Future<void> _syncChapter(String chapterId) async {
    // TODO: embedding 功能暂时屏蔽
    return;
    // final embeddingModel = _embeddingModel;
    // if (embeddingModel == null) {
    //   debugPrint(
    //     '[ChapterEmbeddingSyncQueue] _syncChapter skipped for '
    //     'chapter $chapterId — embeddingModel is null',
    //   );
    //   await _contentService.updateChapterEmbeddingSyncStatus(
    //     chapterId: chapterId,
    //     status: chapterEmbeddingSyncStatusError,
    //   );
    //   return;
    // }
    // final chapter = await _contentService.getChapterById(chapterId);
    // if (chapter == null) {
    //   debugPrint(
    //     '[ChapterEmbeddingSyncQueue] _syncChapter skipped for '
    //     'chapter $chapterId — chapter not found',
    //   );
    //   return;
    // }
    // if (chapter.embeddingSyncStatus == chapterEmbeddingSyncStatusSynced &&
    //     chapter.embeddingSyncModelId == embeddingModel) {
    //   debugPrint(
    //     '[ChapterEmbeddingSyncQueue] _syncChapter skipped for '
    //     'chapter $chapterId — already synced with model $embeddingModel',
    //   );
    //   return;
    // }
    // await _contentService.updateChapterEmbeddingSyncStatus(
    //   chapterId: chapterId,
    //   status: chapterEmbeddingSyncStatusSyncing,
    // );
    // try {
    //   _cachedService ??= await _serviceFactory();
    //   final service = _cachedService;
    //   if (service == null) {
    //     await _contentService.updateChapterEmbeddingSyncStatus(
    //       chapterId: chapterId,
    //       status: chapterEmbeddingSyncStatusError,
    //     );
    //     return;
    //   }
    //   await service.embedding.rebuildChapterEmbeddings(chapterId);
    //   await _contentService.updateChapterEmbeddingSyncStatus(
    //     chapterId: chapterId,
    //     status: chapterEmbeddingSyncStatusSynced,
    //     syncedAt: DateTime.now(),
    //     modelId: embeddingModel,
    //   );
    // } catch (e) {
    //   debugPrint(
    //     '[ChapterEmbeddingSyncQueue] _syncChapter failed for '
    //     'chapter $chapterId: $e',
    //   );
    //   await _contentService.updateChapterEmbeddingSyncStatus(
    //     chapterId: chapterId,
    //     status: chapterEmbeddingSyncStatusError,
    //   );
    // }
  }
}
