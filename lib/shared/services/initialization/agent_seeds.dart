// 职责: 使用当前默认值创建或恢复系统内置 Agent。
// 关联文件:
//   lib/shared/services/builtin_agent_service.dart
//   lib/shared/services/app_initialization.dart
//   lib/shared/database/app_database.dart
import '../../database/app_database.dart';
import '../builtin_agent_service.dart';

Future<void> seedDefaultGlobalAgents(AppDatabase database) {
  return BuiltinAgentService(database).seedMissingGlobalAgents();
}

/// 用户主动恢复系统内置 Agent。
///
/// [overwriteExisting] 为 false 时只补回缺失的系统 Agent，返回新增数量；
/// 为 true 时把所有系统 Agent 重置为当前版本默认值，返回系统 Agent 总数。
/// 不影响用户自定义 Agent。
Future<int> restoreDefaultGlobalAgents(
  AppDatabase database, {
  required bool overwriteExisting,
}) {
  return BuiltinAgentService(
    database,
  ).restoreGlobalAgents(overwriteExisting: overwriteExisting);
}
