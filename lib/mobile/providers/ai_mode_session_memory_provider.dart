// 职责: 移动端作品内 AI 五模式 tab 切换时的进程内会话记忆（novelId → mode → sessionId）。
// 关联文件:
//   lib/mobile/widgets/mobile_ai_mode.dart
//   lib/mobile/widgets/mobile_ai_mode_switch_strip.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/models/ai_chat_session_id.dart
//   lib/shared/models/ai_session_mode.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/ai_chat_session_id.dart';
import '../../shared/models/ai_session_mode.dart';

/// 可写入模式记忆的真实会话 id（排除未落库的临时 draft）。
bool isRememberableAiModeSessionId(String? sessionId) {
  if (sessionId == null || sessionId.isEmpty) {
    return false;
  }
  return !isTemporaryAiChatSessionId(sessionId);
}

/// 单作品下各 AI 模式上次停留的会话 id（仅进程内，不持久化）。
class MobileAiModeSessionMemory extends Notifier<Map<AiSessionMode, String>> {
  MobileAiModeSessionMemory(this.novelId);

  final String novelId;

  @override
  Map<AiSessionMode, String> build() => const {};

  /// 记录 [mode] 当前会话；null / 临时 draft 则清除该模式记忆。
  void remember(AiSessionMode mode, String? sessionId) {
    if (!isRememberableAiModeSessionId(sessionId)) {
      clear(mode);
      return;
    }
    final next = Map<AiSessionMode, String>.of(state);
    next[mode] = sessionId!;
    state = next;
  }

  String? sessionIdFor(AiSessionMode mode) => state[mode];

  void clear(AiSessionMode mode) {
    if (!state.containsKey(mode)) {
      return;
    }
    final next = Map<AiSessionMode, String>.of(state);
    next.remove(mode);
    state = next;
  }
}

/// 按作品隔离的模式会话记忆。keepAlive：tab pushReplacement 后仍需读到上次 id；
/// 每作品仅持有小型 Map，无 stream/client；离开作品不主动释放（进程结束即丢）。
final mobileAiModeSessionMemoryProvider =
    NotifierProvider.family<
      MobileAiModeSessionMemory,
      Map<AiSessionMode, String>,
      String
    >(MobileAiModeSessionMemory.new);
