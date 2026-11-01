// 职责: 判断是否应在 orchestrator 系统提示中展示「初始化设置」(setup_phase) 段落
// 关联文件:
//   lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart
//   lib/shared/database/novel_content_daos/novel_state_dao.dart
//   lib/shared/models/ai_chat_models.dart
//   assets/prompts/agent/orchestrator.md

/// 控制无 agent rules 时 setup_phase 提示的展示窗口，避免用户坚持跳过规则后反复打扰。
///
/// [novelChatSessionCount] 为当前小说 chat 会话总数（见 [novelChatSessionCountProvider]）。
/// [novelOnboardingEligible] 来自 NovelStates 表 key=`novel_onboarding` 的 status
/// 是否为 `eligible`；只有正常新建的小说才会被写入此状态，导入小说不写。
abstract final class SetupPhaseGate {
  /// 会话数超过此值后不再注入 setup 引导。
  static const int maxNovelChatSessions = 3;

  static bool shouldShow({
    required bool hasNovel,
    required bool hasAgentRules,
    required bool novelOnboardingEligible,
    int? novelChatSessionCount,
  }) {
    if (!novelOnboardingEligible || !hasNovel || hasAgentRules) {
      return false;
    }
    final sessions = novelChatSessionCount;
    if (sessions == null) {
      return false;
    }
    return sessions <= maxNovelChatSessions;
  }
}
