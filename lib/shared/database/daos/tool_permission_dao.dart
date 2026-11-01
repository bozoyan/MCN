// 职责: 按固定作用域身份保存、继承和恢复工具权限规则，保持规则身份不变。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/tool_permission.dart
//   lib/shared/services/tool_permissions.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart';
import '../../models/tool_permission.dart';
import '../../logger/app_logger.dart';
import '../../utils/random_id.dart';
import '../app_database.dart';
part 'tool_permission_dao.drift.dart';

final _log = AppLogger.forModule('ToolPermissionDao');

@DriftAccessor(tables: [ToolPermissionRules])
class ToolPermissionDao extends DatabaseAccessor<AppDatabase>
    with _$ToolPermissionDaoMixin {
  ToolPermissionDao(super.db);
  SimpleSelectStatement<$ToolPermissionRulesTable, ToolPermissionRule> _scope(
    ToolPermissionScope scope,
  ) => select(toolPermissionRules)
    ..where(
      (t) =>
          t.scopeType.equalsValue(scope.type) &
          t.workId.equals(scope.workId) &
          t.scopeId.equals(scope.id),
    );
  Future<List<ToolPermissionRule>> rules(ToolPermissionScope scope) => (_scope(
    scope,
  )..where((t) => t.deletedAt.equals(notDeletedSentinel))).get();
  Stream<List<ToolPermissionRule>> watch(ToolPermissionScope scope) => (_scope(
    scope,
  )..where((t) => t.deletedAt.equals(notDeletedSentinel))).watch();
  Future<void> setRule(
    String action,
    ToolPermissionScope scope,
    ToolPermissionDecision? decision,
  ) async {
    scope.validate();
    if (!toolPermissionActions.contains(action)) {
      throw const FormatException('Unknown permission action.');
    }
    try {
      await transaction(() async {
        final current = await (_scope(
          scope,
        )..where((t) => t.action.equals(action))).getSingleOrNull();
        final now = DateTime.now();
        if (current == null) {
          if (decision == null) {
            return;
          }
          await into(toolPermissionRules).insert(
            ToolPermissionRulesCompanion.insert(
              id: buildRandomId('permission'),
              action: action,
              scopeType: scope.type,
              workId: scope.workId,
              scopeId: scope.id,
              decision: decision,
            ),
          );
        } else {
          await (update(
            toolPermissionRules,
          )..where((t) => t.id.equals(current.id))).write(
            ToolPermissionRulesCompanion(
              decision: decision == null
                  ? const Value.absent()
                  : Value(decision),
              deletedAt: Value(decision == null ? now : notDeletedSentinel),
              updatedAt: Value(now),
            ),
          );
        }
      });
    } catch (error, stack) {
      _log.error(
        '[DB] table=tool_permission_rules op=INSERT,UPDATE scope=${scope.type.name}/${scope.id} action=$action',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
