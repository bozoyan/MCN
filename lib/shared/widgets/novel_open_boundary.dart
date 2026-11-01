// 职责: 页面首次读取作品内容前登记打开引用，并在等待维护事务期间显示加载界面。
// 关联文件:
//   lib/shared/providers/novel_maintenance_providers.dart
//   lib/shared/services/novel_maintenance_coordinator.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/novel_maintenance_providers.dart';
import '../theme/theme.dart';

class NovelOpenBoundary extends HookConsumerWidget {
  const NovelOpenBoundary({
    super.key,
    required this.novelId,
    required this.child,
  });

  final String novelId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(novelMaintenanceCoordinatorProvider);
    final lease = useMemoized(() => coordinator.open(novelId), [
      coordinator,
      novelId,
    ]);
    useEffect(() => lease.release, [lease]);
    final readiness = useFuture(lease.ready, preserveState: false);
    if (!lease.initiallyReady &&
        readiness.connectionState != ConnectionState.done) {
      final colors = RevericTheme.colorsOf(context);
      return ColoredBox(
        color: colors.canvas,
        child: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    return child;
  }
}
