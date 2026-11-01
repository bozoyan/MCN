// 职责: 为应用内 Codemode 限制活跃实例和等待队列，并在原生收口后释放名额。
// 关联文件:
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/providers/codemode_provider.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import 'dart:async';
import 'dart:collection';

import '../../../agent/agent_tool_dispatcher.dart';

class CodemodeAdmissionException implements Exception {
  const CodemodeAdmissionException(this.errorCode);
  final String errorCode;
}

class CodemodeLease {
  CodemodeLease._(this._scheduler);
  final CodemodeScheduler _scheduler;
  Future<void>? _release;

  /// A stalled native settlement retains its slot; it is never replaced.
  Future<void> releaseAfter(Future<void> settled) =>
      _release ??= settled.then((_) => _scheduler._release());
}

class CodemodeScheduler {
  CodemodeScheduler({
    required this.maxActive,
    this.maxQueued = 8,
    this.waitTimeout = const Duration(seconds: 15),
  }) : assert(maxActive > 0),
       assert(maxQueued >= 0);
  final int maxActive;
  final int maxQueued;
  final Duration waitTimeout;
  final Queue<_Waiter> _queue = Queue();
  int _active = 0;
  bool _disposed = false;

  int get activeCount => _active;
  int get queuedCount => _queue.length;

  Future<CodemodeLease> acquire({AgentCancellationToken? cancellationToken}) {
    if (cancellationToken?.isCancellationRequested == true || _disposed) {
      return Future.error(const CodemodeAdmissionException('user_cancelled'));
    }
    if (_active < maxActive) {
      _active++;
      return Future.value(CodemodeLease._(this));
    }
    if (_queue.length >= maxQueued) {
      return Future.error(const CodemodeAdmissionException('codemode_busy'));
    }
    final waiter = _Waiter();
    _queue.add(waiter);
    void reject(String code) {
      if (!_queue.remove(waiter)) {
        return;
      }
      waiter.dispose();
      waiter.result.completeError(CodemodeAdmissionException(code));
    }

    waiter.timer = Timer(waitTimeout, () => reject('codemode_busy'));
    waiter.unlink = cancellationToken?.onCancel(() => reject('user_cancelled'));
    return waiter.result.future;
  }

  void _release() {
    _active--;
    if (_disposed || _queue.isEmpty) {
      return;
    }
    final waiter = _queue.removeFirst();
    waiter.dispose();
    _active++;
    waiter.result.complete(CodemodeLease._(this));
  }

  void dispose() {
    _disposed = true;
    for (final waiter in _queue) {
      waiter.dispose();
      waiter.result.completeError(
        const CodemodeAdmissionException('user_cancelled'),
      );
    }
    _queue.clear();
  }
}

class _Waiter {
  final Completer<CodemodeLease> result = Completer<CodemodeLease>();
  Timer? timer;
  void Function()? unlink;
  void dispose() {
    timer?.cancel();
    unlink?.call();
  }
}
