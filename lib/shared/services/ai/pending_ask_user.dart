// 职责: 管理单次 AskUser 的等待截止、提醒与一次性完成。
// 关联文件:
//   lib/shared/models/ask_user_models.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/providers/ai_providers.dart
import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/ask_user_models.dart';

class PendingAskUser {
  PendingAskUser({
    required this.request,
    required this.runId,
    DateTime Function()? now,
    this.onReminder,
    this.onResolved,
  }) : _now = now ?? DateTime.now {
    startedAt = _now();
  }

  static const reminderDelay = Duration(minutes: 10);
  static const timeout = Duration(minutes: 30);
  final String instanceId = const Uuid().v4();
  final AskUserRequest request;
  final int runId;
  final DateTime Function() _now;
  final void Function(PendingAskUser pending)? onReminder;
  final void Function(PendingAskUser pending, AskUserResult result)? onResolved;
  late final DateTime startedAt;
  final _completer = Completer<AskUserResult>();
  Timer? _reminderTimer;
  Timer? _timeoutTimer;
  bool _reminded = false;
  bool _started = false;

  String get blockId => 'askuser_${runId}_${instanceId}_${request.callId}';
  Future<AskUserResult> get future => _completer.future;
  bool get isCompleted => _completer.isCompleted;

  void start() {
    if (_started || isCompleted) {
      return;
    }
    _started = true;
    _reminderTimer = Timer(reminderDelay, checkDeadline);
    _timeoutTimer = Timer(timeout, checkDeadline);
    checkDeadline();
  }

  /// Also called on resume and before accepting a user response.
  void checkDeadline() {
    if (isCompleted) {
      return;
    }
    final elapsed = _now().difference(startedAt);
    if (elapsed >= timeout) {
      _resolve(AskUserResult.timeout(request.questions));
    } else if (elapsed >= reminderDelay && !_reminded) {
      _reminded = true;
      onReminder?.call(this);
    }
  }

  /// Rechecked after notification initialization and permission prompts.
  bool notificationIsCurrent({required bool reminder}) {
    if (isCompleted) {
      return false;
    }
    final elapsed = _now().difference(startedAt);
    return elapsed < timeout &&
        (reminder ? elapsed >= reminderDelay : elapsed < reminderDelay);
  }

  void complete(AskUserResult result) {
    checkDeadline();
    _resolve(result);
  }

  /// Run interruption is distinct from a user response and does not auto-select.
  void cancel() {
    _resolve(
      const AskUserResult(
        ok: false,
        cancelled: true,
        resolution: AskUserResolution.interrupted,
      ),
    );
  }

  void _resolve(AskUserResult result) {
    if (isCompleted) {
      return;
    }
    _reminderTimer?.cancel();
    _timeoutTimer?.cancel();
    _completer.complete(result);
    onResolved?.call(this, result);
  }
}
