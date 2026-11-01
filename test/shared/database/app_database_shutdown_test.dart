// 职责: 主数据库退出回归测试 — 确保暂停的查询流不会阻塞 SQLite executor 关闭。
// 关联文件:
//   lib/shared/database/app_database.dart

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';

void main() {
  test('process exit does not wait for a paused query stream', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final firstResult = Completer<void>();
    final subscription = database.novelDao.watchAll().listen((_) {
      if (!firstResult.isCompleted) {
        firstResult.complete();
      }
    });
    await firstResult.future;
    subscription.pause();

    await database.closeExecutorForProcessExitForTesting().timeout(
      const Duration(milliseconds: 100),
    );

    subscription.resume();
    await subscription.cancel();
    await database.close();
  });
}
