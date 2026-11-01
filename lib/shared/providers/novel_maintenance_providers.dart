// 职责: 为页面进入边界与清理调度器共享同一个作品维护协调器。
// 关联文件:
//   lib/shared/services/novel_maintenance_coordinator.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/novel_open_boundary.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/novel_maintenance_coordinator.dart';

final novelMaintenanceCoordinatorProvider =
    Provider<NovelMaintenanceCoordinator>(
      (ref) => NovelMaintenanceCoordinator(),
    );
