// 职责: Title Prompt Use Case — 构建所有标题生成的 system prompt
// 关联文件:
//   lib/shared/services/ai/monologue_orchestrator.dart
//   lib/shared/services/ai/roleplay_orchestrator.dart
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart

class TitlePromptUseCase {
  const TitlePromptUseCase();

  String councilTitle() {
    return '你负责给一场智能体讨论命名。根据讨论话题和参与角色生成一个简短的中文标题，限制 12 个字以内，不要标点，不要解释，只输出标题本身。';
  }

  String theaterTitle() {
    return '你负责给一场小剧场表演命名。根据场景描述和角色生成一个简短的中文标题，限制 12 个字以内，不要标点，不要解释，只输出标题本身。';
  }

  String roleplayTitle() {
    return '你负责给一段角色扮演对话命名。根据角色和对话内容生成一个简短的中文标题，限制 12 个字以内，不要标点，不要解释，只输出标题本身。';
  }

  String monologueTitle() {
    return '你负责给一段角色内心独白命名。根据角色和话题生成一个简短的中文标题，限制 12 个字以内，不要标点，不要解释，只输出标题本身。';
  }
}
