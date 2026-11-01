// 职责: 制片子页面挂载期间上报名称与调度 ID，切换和卸载时清除对应上下文。
// 关联文件:
//   lib/shared/providers/production_view.dart
//   lib/desktop/features/editing/region.dart
//   lib/shared/widgets/screenplay/director_workspace.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/production_view.dart';

void useProductionSubpage(
  WidgetRef ref,
  String databasePath,
  String label, {
  String? stagingId,
}) {
  // watch notifier 只为保活，状态变化不会让子页面重建。
  final subpage = ref.watch(productionSubpageProvider(databasePath).notifier);
  // build 期间不能改 provider，写入都延后到帧末。
  useEffect(() {
    final page = (label: label, stagingId: stagingId);
    var mounted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        subpage.set(page);
      }
    });
    return () {
      mounted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => subpage.clear(page));
    };
  }, [subpage, label, stagingId]);
}
