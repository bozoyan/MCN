// 职责: 在作品进入边界与维护提交之间协调打开引用、读取等待和清理许可。
// 关联文件:
//   lib/shared/services/storage_cleanup_service.dart

import 'dart:async';
import '../logger/app_logger.dart';

class NovelMaintenanceCoordinator {
  final Map<String, int> _openReferences = {};
  final Map<String, Completer<void>> _commits = {};

  bool isOpen(String novelId) => _openReferences.containsKey(novelId);

  /// 同步登记打开意图；首次读取必须等待 ready，页面离开时释放引用。
  NovelOpenLease open(String novelId) {
    _openReferences.update(novelId, (count) => count + 1, ifAbsent: () => 1);
    final commit = _commits[novelId];
    final wait = Stopwatch()..start();
    final ready = commit == null
        ? Future<void>.value()
        : commit.future.then((_) {
            AppLogger.forModule('StorageCleanup').info(
              'novel open waited novel=$novelId durationMs=${wait.elapsedMilliseconds}',
            );
          });
    return NovelOpenLease._(ready, commit == null, () {
      final remaining = _openReferences[novelId]! - 1;
      if (remaining == 0) {
        _openReferences.remove(novelId);
      } else {
        _openReferences[novelId] = remaining;
      }
    });
  }

  /// 只覆盖当前树的复核与提交，不排队抢占已登记的打开意图。
  NovelCleanupPermit? tryAcquireCleanup(String novelId) {
    if (isOpen(novelId) || _commits.containsKey(novelId)) {
      return null;
    }
    final completion = Completer<void>();
    _commits[novelId] = completion;
    return NovelCleanupPermit._(() {
      _commits.remove(novelId);
      completion.complete();
    });
  }
}

class NovelOpenLease {
  NovelOpenLease._(this.ready, this.initiallyReady, this._release);

  final Future<void> ready;
  final bool initiallyReady;
  void Function()? _release;

  void release() {
    final release = _release;
    _release = null;
    release?.call();
  }
}

class NovelCleanupPermit {
  NovelCleanupPermit._(this._release);

  void Function()? _release;

  void release() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
