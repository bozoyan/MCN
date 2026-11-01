// 职责: AI 聊天面板 — 解析当前 Agent Profile 与可用 SubAgent。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/models/agent_profile.dart
//   lib/shared/models/subagent.dart
part of 'panel.dart';

extension _AiChatPanelAgentSelection on AiChatPanel {
  String? _resolvePersistedAgentSlug(dynamic session) {
    if (AiSessionMode.fromString(session.mode).isChat) {
      return builtinAgentSlugOrchestrator;
    }
    if (session.agentSlug != null && session.agentSlug!.isNotEmpty) {
      return session.agentSlug;
    }
    return null;
  }

  List<SubAgent> _runtimeChatSubAgents(List<SubAgent> subagents) {
    return subagents
        .where(
          (agent) => agent.enabled && agent.mode == AiSessionMode.chat.value,
        )
        .toList(growable: false);
  }

  List<SubAgent> _userVisibleChatSubAgents(List<SubAgent> subagents) {
    return _runtimeChatSubAgents(
      subagents,
    ).where(isUserVisibleSubAgent).toList(growable: false);
  }
}
