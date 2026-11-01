// 职责: Prompt 模板与 Prompt 门面 Provider — 暴露 PromptTemplateService 与 AiPromptService 实例
// 关联文件:
//   lib/shared/services/ai/prompt_template.dart
//   lib/shared/services/ai/prompts/ai_prompt_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai/prompt_template.dart';
import '../services/ai/prompts/ai_prompt_service.dart';
import '../services/ai/prompts/prompt_renderer.dart';

final promptTemplateServiceProvider = Provider<PromptTemplateService>((ref) {
  return PromptTemplateService.instance;
});

final aiPromptServiceProvider = Provider<AiPromptService>((ref) {
  final templates = ref.watch(promptTemplateServiceProvider);
  return AiPromptService(renderer: PromptRenderer(templates: templates));
});
