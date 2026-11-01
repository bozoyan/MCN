// 职责: Assistant system prompt 渲染 — 聊天通道中枢身份、工具集、意图分发规则
// 关联文件:
//   lib/shared/services/ai/prompts/ai_prompt_service.dart
//   lib/shared/services/ai/prompts/prompt_id.dart
//   lib/shared/services/ai/prompts/prompt_renderer.dart
//   assets/prompts/agent/assistant.md

import '../prompt_id.dart';
import '../prompt_renderer.dart';

class AssistantPromptUseCase {
  const AssistantPromptUseCase({this.renderer});

  final PromptRenderer? renderer;

  String system({String? userName}) {
    return renderer!.render(PromptId.agentAssistant, <String, dynamic>{
      'user_name': userName?.trim().isNotEmpty == true
          ? userName!.trim()
          : '用户',
    });
  }
}
