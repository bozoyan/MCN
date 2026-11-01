// 职责: 执行跨作品智能体规则复制 — 去重、追加排序、生成新 ID 并写入目标内容库。
// 关联文件:
//   lib/shared/models/agent_rule.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/utils/random_id.dart
//   lib/desktop/widgets/agent_management/agent_rule_copy_dialog.dart
//   lib/mobile/widgets/agent_rule_copy_sheet.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/state-management.md
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../utils/random_id.dart';
import 'novel_content.dart';

final _log = AppLogger.forModule('AgentRuleCopy');

/// 将选中的来源规则追加到目标作品，跳过目标中已有同名规则。
///
/// 返回实际写入的规则数量。写入顺序沿用 [currentRules] 的最大排序值之后，
/// 不复用来源规则 ID，避免不同内容库之间发生主键冲突。
Future<int> copyAgentRulesToNovel({
  required NovelContentService targetService,
  required List<AgentRule> currentRules,
  required List<AgentRule> sourceRules,
  required String sourcePath,
  required String targetPath,
}) async {
  final existingNames = {for (final rule in currentRules) rule.name};
  final rules = sourceRules
      .where((rule) => existingNames.add(rule.name))
      .toList(growable: false);
  if (rules.isEmpty) {
    return 0;
  }

  var sortOrder =
      currentRules.fold<int>(
        -1,
        (max, rule) => rule.sortOrder > max ? rule.sortOrder : max,
      ) +
      1;
  final now = DateTime.now();
  var copied = 0;
  try {
    for (final rule in rules) {
      await targetService.upsertAgentRule(
        AgentRule(
          id: buildRandomId('agent_rule'),
          name: rule.name,
          content: rule.content,
          enabled: rule.enabled,
          sortOrder: sortOrder,
          createdAt: now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
      sortOrder += 1;
      copied += 1;
    }
  } catch (error, stackTrace) {
    _log.error(
      '[DB] table=agent_rules operation=INSERT '
      'source=$sourcePath target=$targetPath '
      'copied=$copied/${rules.length} error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
  return copied;
}
