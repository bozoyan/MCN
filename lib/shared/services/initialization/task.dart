// 职责: 应用初始化任务类型定义 — AppInitializationTask 基类和 Runner typedef
// 关联文件:
//   lib/shared/services/initialization/app_initialization.dart

import '../../database/app_database.dart';

typedef AppInitializationRunner = Future<void> Function(AppDatabase database);

class AppInitializationTask {
  const AppInitializationTask({required this.id, required this.run});

  final String id;
  final AppInitializationRunner run;
}
