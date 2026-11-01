// 职责: Memory 定时任务调度器 — 按配置间隔周期性触发记忆提取与消化，支持活跃优先、错误重试、并发限制
// 关联文件:
//   lib/shared/services/ai/memory_extraction_service.dart
//   lib/shared/services/ai/memory_dreaming_service.dart
//   lib/shared/database/daos/app_state_dao.dart

import 'dart:async';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../logger/app_logger.dart';

final _log = AppLogger.forModule('MemoryScheduler');

const _memStateKeyExtractionPrefix = 'mem_last_extraction_';
const _memStateKeyDreamingPrefix = 'mem_last_dreaming_';

class MemoryScheduler {
  MemoryScheduler({
    required this._db,
    required this._onExtract,
    required this._onDream,
    this._extractionIntervalMinutes = 60,
    this._dreamingIntervalHours = 24,
    this._extractionEnabled = true,
    this._dreamingEnabled = true,
    int checkIntervalSeconds = 30,
    this._maxConcurrentTasks = 2,
    this._maxRetries = 2,
  }) : _checkInterval = Duration(seconds: checkIntervalSeconds);

  final AppDatabase _db;
  final Future<void> Function(String novelId) _onExtract;
  final Future<void> Function(String novelId) _onDream;
  final Duration _checkInterval;
  final int _maxConcurrentTasks;
  final int _maxRetries;

  int _extractionIntervalMinutes;
  int _dreamingIntervalHours;
  bool _extractionEnabled;
  bool _dreamingEnabled;

  Timer? _timer;
  bool _disposed = false;

  final _extractingNovels = <String>{};
  final _dreamingNovels = <String>{};
  final _extractRetryCount = <String, int>{};
  final _dreamRetryCount = <String, int>{};

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_checkInterval, (_) => _tick());
    _log.info(
      'started checkInterval=${_checkInterval.inSeconds}s'
      ' extractInterval=$_extractionIntervalMinutes m'
      ' extractEnabled=$_extractionEnabled'
      ' dreamInterval=$_dreamingIntervalHours h'
      ' dreamEnabled=$_dreamingEnabled'
      ' maxConcurrent=$_maxConcurrentTasks'
      ' maxRetries=$_maxRetries',
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _log.info('stopped');
  }

  void dispose() {
    _disposed = true;
    stop();
    _extractingNovels.clear();
    _dreamingNovels.clear();
    _extractRetryCount.clear();
    _dreamRetryCount.clear();
  }

  void updateConfig({
    int? extractionIntervalMinutes,
    int? dreamingIntervalHours,
    bool? extractionEnabled,
    bool? dreamingEnabled,
  }) {
    if (extractionIntervalMinutes != null) {
      _extractionIntervalMinutes = extractionIntervalMinutes;
    }
    if (dreamingIntervalHours != null) {
      _dreamingIntervalHours = dreamingIntervalHours;
    }
    if (extractionEnabled != null) {
      _extractionEnabled = extractionEnabled;
    }
    if (dreamingEnabled != null) {
      _dreamingEnabled = dreamingEnabled;
    }
  }

  Future<void> forceExtract(String novelId) async {
    if (_disposed) return;
    if (_extractingNovels.length >= _maxConcurrentTasks) {
      _log.warning(
        'force extract skipped for novelId=$novelId, '
        'concurrent limit reached (${_extractingNovels.length}/$_maxConcurrentTasks)',
      );
      return;
    }
    if (_extractingNovels.contains(novelId)) return;
    _extractingNovels.add(novelId);
    _extractRetryCount.remove(novelId);
    try {
      _log.info('force extract novelId=$novelId');
      await _onExtract(novelId);
      await _db.appStateDao.set(
        key: '$_memStateKeyExtractionPrefix$novelId',
        value: DateTime.now().toIso8601String(),
      );
    } finally {
      _extractingNovels.remove(novelId);
    }
  }

  Future<void> forceDream(String novelId) async {
    if (_disposed) return;
    if (_dreamingNovels.length >= _maxConcurrentTasks) {
      _log.warning(
        'force dream skipped for novelId=$novelId, '
        'concurrent limit reached (${_dreamingNovels.length}/$_maxConcurrentTasks)',
      );
      return;
    }
    if (_dreamingNovels.contains(novelId)) return;
    _dreamingNovels.add(novelId);
    _dreamRetryCount.remove(novelId);
    try {
      _log.info('force dream novelId=$novelId');
      await _onDream(novelId);
      await _db.appStateDao.set(
        key: '$_memStateKeyDreamingPrefix$novelId',
        value: DateTime.now().toIso8601String(),
      );
    } finally {
      _dreamingNovels.remove(novelId);
    }
  }

  Future<void> _tick() async {
    if (_disposed) return;
    try {
      final query = _db.select(_db.novels)
        ..where((table) => table.deletedAt.equals(notDeletedSentinel))
        ..orderBy([
          (table) => OrderingTerm(
            expression: table.updatedAt,
            mode: OrderingMode.desc,
          ),
        ]);
      final novels = await query.get();
      for (final novel in novels) {
        if (_disposed) return;
        await _maybeExtract(novel.id);
        await _maybeDream(novel.id);
      }
    } catch (e, stack) {
      _log.error('tick error: $e', error: e, stackTrace: stack);
    }
  }

  Future<void> _maybeExtract(String novelId) async {
    if (!_extractionEnabled) return;
    if (_extractingNovels.contains(novelId)) return;
    if (_extractingNovels.length >= _maxConcurrentTasks) return;

    final lastRaw = await _db.appStateDao.get(
      '$_memStateKeyExtractionPrefix$novelId',
    );
    final lastTime = lastRaw != null ? DateTime.tryParse(lastRaw) : null;
    final nextDue = lastTime?.add(
      Duration(minutes: _extractionIntervalMinutes),
    );
    if (nextDue != null && DateTime.now().isBefore(nextDue)) return;

    _extractingNovels.add(novelId);
    try {
      if (_log.isDebugEnabled) {
        _log.debug('extracting for novelId=$novelId');
      }
      await _onExtract(novelId);
      await _db.appStateDao.set(
        key: '$_memStateKeyExtractionPrefix$novelId',
        value: DateTime.now().toIso8601String(),
      );
      _extractRetryCount.remove(novelId);
    } catch (e) {
      final retries = _extractRetryCount[novelId] ?? 0;
      if (retries < _maxRetries) {
        _extractRetryCount[novelId] = retries + 1;
        _log.warning(
          'extract error novelId=$novelId (retry ${retries + 1}/$_maxRetries): $e',
        );
      } else {
        _extractRetryCount.remove(novelId);
        _log.error(
          'extract failed novelId=$novelId after $_maxRetries retries: $e',
        );
        await _db.appStateDao.set(
          key: '$_memStateKeyExtractionPrefix$novelId',
          value: DateTime.now().toIso8601String(),
        );
      }
    } finally {
      _extractingNovels.remove(novelId);
    }
  }

  Future<void> _maybeDream(String novelId) async {
    if (!_dreamingEnabled) return;
    if (_dreamingNovels.contains(novelId)) return;
    if (_dreamingNovels.length >= _maxConcurrentTasks) return;

    final lastRaw = await _db.appStateDao.get(
      '$_memStateKeyDreamingPrefix$novelId',
    );
    final lastTime = lastRaw != null ? DateTime.tryParse(lastRaw) : null;
    final nextDue = lastTime?.add(Duration(hours: _dreamingIntervalHours));
    if (nextDue != null && DateTime.now().isBefore(nextDue)) return;

    _dreamingNovels.add(novelId);
    try {
      if (_log.isDebugEnabled) {
        _log.debug('dreaming for novelId=$novelId');
      }
      await _onDream(novelId);
      await _db.appStateDao.set(
        key: '$_memStateKeyDreamingPrefix$novelId',
        value: DateTime.now().toIso8601String(),
      );
      _dreamRetryCount.remove(novelId);
    } catch (e) {
      final retries = _dreamRetryCount[novelId] ?? 0;
      if (retries < _maxRetries) {
        _dreamRetryCount[novelId] = retries + 1;
        _log.warning(
          'dream error novelId=$novelId (retry ${retries + 1}/$_maxRetries): $e',
        );
      } else {
        _dreamRetryCount.remove(novelId);
        _log.error(
          'dream failed novelId=$novelId after $_maxRetries retries: $e',
        );
        await _db.appStateDao.set(
          key: '$_memStateKeyDreamingPrefix$novelId',
          value: DateTime.now().toIso8601String(),
        );
      }
    } finally {
      _dreamingNovels.remove(novelId);
    }
  }
}
