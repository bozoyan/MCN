// 职责: Debug-only Reveric provider 配置 — 暴露真实模型的可控异常注入入口
// 关联文件:
//   lib/shared/models/ai_provider.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/services/ai/provider_initializer.dart

const debugDeepseekTruncatedProviderId = 'debug_deepseek_truncated';
const debugDeepseekPartialToolProviderId = 'debug_deepseek_partial_tool';
const debugOpenAiResponsesThinkingOnlyProviderId =
    'debug_openai_responses_thinking_only';
const debugOpenAiResponsesPartialToolProviderId =
    'debug_openai_responses_partial_tool';

enum DebugAiProviderScenario {
  truncatedText,
  partialToolWithoutThinking,
  thinkingOnly,
  partialToolWithThinking,
}

DebugAiProviderScenario? debugAiProviderScenarioForId(String id) {
  return switch (id) {
    debugDeepseekTruncatedProviderId => DebugAiProviderScenario.truncatedText,
    debugDeepseekPartialToolProviderId =>
      DebugAiProviderScenario.partialToolWithoutThinking,
    debugOpenAiResponsesThinkingOnlyProviderId =>
      DebugAiProviderScenario.thinkingOnly,
    debugOpenAiResponsesPartialToolProviderId =>
      DebugAiProviderScenario.partialToolWithThinking,
    _ => null,
  };
}

bool isDebugAiProviderId(String id) {
  return debugAiProviderScenarioForId(id) != null;
}
