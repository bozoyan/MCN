// 职责: AI 会话模式权限模型，负责定义各模式可用工具与提示说明。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/chat.dart

import '../services/ai/builtin_agent_tools.dart';

enum AiSessionMode {
  chat('chat'),
  council('council'),
  monologue('monologue'),
  theater('theater'),
  roleplay('roleplay');

  const AiSessionMode(this.value);

  final String value;

  static AiSessionMode fromString(String value) => switch (value) {
    'council' => council,
    'monologue' => monologue,
    'theater' => theater,
    'roleplay' => roleplay,
    'chat' => chat,
    _ => chat,
  };

  bool get isChat => this == chat;
  bool get canRead => true;
  bool get canWrite => this == chat;
  bool get canManageRelations => this == chat;
  bool get isCouncil => this == council;
  bool get isMonologue => this == monologue;
  bool get isTheater => this == theater;
  bool get isRoleplay => this == roleplay;
  bool get isSpecialMode =>
      this == council ||
      this == monologue ||
      this == theater ||
      this == roleplay;

  bool canUseTool(String toolName) => switch (this) {
    chat => true,
    council ||
    monologue ||
    theater ||
    roleplay => !builtinSpecialModeDisabledToolNames.contains(toolName),
  };

  String get promptHint => switch (this) {
    chat => '当前处于 chat 模式，由 Chat Orchestrator 编排回答、工具调用和 SubAgent 委派。',
    council => '当前处于 council 模式，多个 AI 专家将围绕你的话题展开讨论。',
    monologue => '当前处于 monologue 模式，AI 将代入小说角色，以第一人称描述内心活动与行动。',
    theater => '当前处于 theater 模式，多个小说角色将在场景中互动表演。',
    roleplay => '当前处于 roleplay 模式，你将与小说角色进行一对一对话互动。',
  };
}
