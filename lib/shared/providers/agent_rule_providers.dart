// 职责: 暴露 AgentRule 的实时读取 Provider。
// 关联文件:
//   lib/shared/models/agent_rule.dart
//   lib/shared/services/novel_content.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/agent_rule.dart';
import 'novel_providers.dart';

part 'agent_rule_providers.g.dart';

/// AgentRule 实时流
@riverpod
Stream<List<AgentRule>> agentRulesStream(Ref ref, String databasePath) {
  final database = ref.watch(novelContentServiceProvider(databasePath));
  return database.watchAgentRules();
}
