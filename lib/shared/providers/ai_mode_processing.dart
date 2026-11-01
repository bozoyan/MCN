// 职责: 跨 AI 互动 mode 的后台处理追踪 — 汇总运行中的 session、前台可见 session，并在后台完成时发出系统通知。
// 关联文件:
//   lib/shared/models/ai_session_mode.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/services/system_notification_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// select 是 ProviderListenableSelect extension；riverpod_annotation 的导出白名单
// 不含该 extension，需经 hooks_riverpod 引入。
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../localization/locale_keys.dart';
import '../models/ai_session_mode.dart';
import '../services/system_notification_service.dart';

part 'ai_mode_processing.g.dart';

@Riverpod(keepAlive: true)
class AiModeProcessingTracker extends _$AiModeProcessingTracker {
  final Set<String> _foregroundTokens = <String>{};
  bool _appInForeground = true;
  final Set<void Function()> _resumeChecks = {};

  void addResumeCheck(void Function() check) => _resumeChecks.add(check);
  void removeResumeCheck(void Function() check) => _resumeChecks.remove(check);

  bool isViewingSession({
    required AiSessionMode mode,
    required String? sessionId,
  }) {
    return _appInForeground &&
        sessionId != null &&
        _foregroundTokens.contains(token(mode, sessionId));
  }

  @override
  Set<String> build() => const {};

  static String token(AiSessionMode mode, String sessionId) {
    return '${mode.value}:$sessionId';
  }

  void setProcessing({
    required AiSessionMode mode,
    required String sessionId,
    required bool processing,
    bool notifyOnComplete = true,
  }) {
    final entry = token(mode, sessionId);
    final next = Set<String>.from(state);
    final wasProcessing = next.contains(entry);
    if (processing) {
      next.add(entry);
    } else {
      next.remove(entry);
    }
    state = next;
    if (!processing && wasProcessing && notifyOnComplete) {
      _notifyIfBackground(entry);
    }
  }

  void setAppForeground(bool foreground) {
    _appInForeground = foreground;
    if (foreground) {
      for (final check in _resumeChecks.toList()) {
        check();
      }
    }
  }

  void setForegroundSession({
    required AiSessionMode mode,
    required String sessionId,
    required bool foreground,
  }) {
    if (sessionId.isEmpty) {
      return;
    }
    final entry = token(mode, sessionId);
    if (foreground) {
      _foregroundTokens.add(entry);
    } else {
      _foregroundTokens.remove(entry);
    }
  }

  void _notifyIfBackground(String entry) {
    // 只有当 app 在前台 且 该 session 在前台(用户在看)时才不通知；
    // app 在后台（最小化/隐藏）时任何 session 完成都通知。
    if (_appInForeground && _foregroundTokens.contains(entry)) {
      return;
    }
    unawaited(
      SystemNotificationService.show(
        identifier:
            'ai_session_completed_${entry}_${DateTime.now().millisecondsSinceEpoch}',
        title: tr(LocaleKeys.aiNotificationSessionCompletedTitle),
        body: tr(LocaleKeys.aiNotificationSessionCompletedBody),
      ),
    );
  }
}

@riverpod
bool anyAiModeProcessing(Ref ref) {
  return ref.watch(aiModeProcessingTrackerProvider).isNotEmpty;
}

/// 某个 session 当前是否有 agent 在处理。
///
/// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
/// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。
@riverpod
bool aiSessionProcessing(
  Ref ref, {
  required AiSessionMode mode,
  required String sessionId,
}) {
  final entry = AiModeProcessingTracker.token(mode, sessionId);
  return ref.watch(
    aiModeProcessingTrackerProvider.select((tokens) => tokens.contains(entry)),
  );
}
