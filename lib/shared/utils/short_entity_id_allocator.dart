// 职责: 在严格插入作品业务实体时处理存量、同批和并发主键 ID 碰撞。
// 关联文件:
//   lib/shared/utils/short_entity_id.dart
//   lib/shared/database/novel_content_database.dart
import 'package:sqlite3/sqlite3.dart';

import 'short_entity_id.dart';

const int shortEntityIdMaxAttempts = 32;
// SQLite extended result code SQLITE_CONSTRAINT_PRIMARYKEY.
const int _sqliteConstraintPrimaryKey = 1555;

class ShortEntityIdAllocationException implements Exception {
  const ShortEntityIdAllocationException(this.type);

  final ShortEntityIdType type;

  @override
  String toString() {
    return 'Unable to allocate a unique short entity ID for ${type.name} '
        'after $shortEntityIdMaxAttempts attempts.';
  }
}

/// 用短 ID 严格插入一个新实体，并返回最终落库的 ID。
///
/// [idExists] 必须查询目标表的全部身份，包括有效行和软删除行；[reservedIds]
/// 用于排除同批已经选中的候选。只有目标表 [tableName].[primaryKeyColumn]
/// 的主键碰撞会换号重试，其他数据库错误会原样抛出。
Future<String> insertWithShortEntityId({
  required ShortEntityIdType type,
  required String tableName,
  String primaryKeyColumn = 'id',
  required Future<bool> Function(String id) idExists,
  required Future<void> Function(String id) insert,
  Set<String>? reservedIds,
  ShortEntityIdBuilder buildId = buildShortEntityId,
}) async {
  for (var attempt = 0; attempt < shortEntityIdMaxAttempts; attempt++) {
    final id = buildId(type);
    if ((reservedIds?.contains(id) ?? false) || await idExists(id)) {
      continue;
    }
    try {
      await insert(id);
      reservedIds?.add(id);
      return id;
    } on SqliteException catch (error) {
      if (_isTargetPrimaryKeyConflict(
        error,
        tableName: tableName,
        primaryKeyColumn: primaryKeyColumn,
      )) {
        continue;
      }
      rethrow;
    }
  }
  throw ShortEntityIdAllocationException(type);
}

bool _isTargetPrimaryKeyConflict(
  SqliteException error, {
  required String tableName,
  required String primaryKeyColumn,
}) {
  if (error.extendedResultCode != _sqliteConstraintPrimaryKey) {
    return false;
  }
  return error.message.contains('$tableName.$primaryKeyColumn');
}
