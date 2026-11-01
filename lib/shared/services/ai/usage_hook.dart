// 职责: Usage hook — 记录所有 Agent LLM token 用量（不拦截额度）。
// 关联文件:
//   lib/shared/agent/agent_hook.dart
//   lib/shared/services/ai/usage_service.dart

import 'dart:async';

import '../../agent/agent_event.dart';
import '../../agent/agent_hook.dart';
import 'usage_service.dart';

typedef UsageSessionValue = String? Function();

class UsageHook extends AgentHook {
  const UsageHook({
    required this.service,
    required this.providerId,
    required this.model,
    required this.sessionId,
    required this.novelId,
    this.source = 'chat',
    this.runId,
    this.runLabel,
    this.onUsageChanged,
  });

  final UsageService service;
  final UsageSessionValue providerId;
  final UsageSessionValue model;
  final UsageSessionValue sessionId;
  final UsageSessionValue novelId;
  final String source;
  final UsageSessionValue? runId;
  final UsageSessionValue? runLabel;
  final void Function()? onUsageChanged;

  UsageHook rebind({
    UsageSessionValue? providerId,
    UsageSessionValue? model,
    UsageSessionValue? sessionId,
    UsageSessionValue? novelId,
    String? source,
    UsageSessionValue? runId,
    UsageSessionValue? runLabel,
  }) {
    return UsageHook(
      service: service,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      sessionId: sessionId ?? this.sessionId,
      novelId: novelId ?? this.novelId,
      source: source ?? this.source,
      runId: runId ?? this.runId,
      runLabel: runLabel ?? this.runLabel,
      onUsageChanged: onUsageChanged,
    );
  }

  @override
  FutureOr<HookAction<AgentRoundResult>> afterLLM(
    AgentRoundResult round,
  ) async {
    final usage = round.usage;
    final currentModel = model();
    final currentProviderId = providerId();
    if (usage == null || !usage.hasData || currentModel == null) {
      return const HookAction.proceed();
    }
    await service.recordUsage(
      providerId: currentProviderId ?? 'unknown',
      model: currentModel,
      usage: usage,
      sessionId: sessionId(),
      novelId: novelId(),
      source: source,
      runId: runId?.call(),
      runLabel: runLabel?.call(),
    );
    onUsageChanged?.call();
    return const HookAction.proceed();
  }
}
