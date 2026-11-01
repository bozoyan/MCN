// 职责: 测试专用 working change 断言助手 — 取当前唯一一条 active working change，
//   用于 AI 工具不再回传 working_change_id 后定位刚 stage 出来的那条变更。
//   必须按 status 过滤：workingChangeDao.getAll() 不过滤状态，
//   commit / reject 都会保留原行，只改 status。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/novel_content_daos/working_change_dao.dart
//   lib/shared/services/working_overlay.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/working_overlay.dart';

/// 断言当前恰好只有一条 active working change，并返回它。
Future<WorkingChange> onlyActiveWorkingChange(NovelContentDatabase db) async {
  final all = await db.workingChangeDao.getAll();
  final active = all
      .where((change) => change.status == workingChangeStatusActive)
      .toList();
  expect(
    active,
    hasLength(1),
    reason:
        'expected exactly one active working change, got '
        '${active.map((change) => change.resourcePath).toList()} '
        '(${all.length} rows total)',
  );
  return active.single;
}

/// [onlyActiveWorkingChange] 的 id 便捷形式。
Future<String> onlyActiveWorkingChangeId(NovelContentDatabase db) async {
  return (await onlyActiveWorkingChange(db)).id;
}
