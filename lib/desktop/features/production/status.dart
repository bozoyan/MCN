// 职责: 为桌面工作区底栏提供当前集的制片统计（计划时长、段数、完成数）。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/desktop/features/screenplay/chrome.dart
//   lib/shared/providers/storyboard.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/app_database.dart' show Novel;
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/providers/storyboard.dart';
import '../../../shared/theme/theme.dart';
import '../screenplay/chrome.dart';

class ProductionStatusItems extends ConsumerWidget {
  const ProductionStatusItems({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final episodeId = ref
        .watch(screenplayWorkspaceStateControllerProvider(novel.id, path))
        .episodeId;
    if (episodeId == null) {
      return const SizedBox.shrink();
    }
    final clips =
        ref.watch(storyboardShotsProvider(path, episodeId)).value ??
        const <ProductionClipRow>[];
    final scenes =
        ref.watch(screenplayScenesProvider(path, episodeId)).value ??
        const <ScreenplaySceneSummary>[];
    final planned = clips.fold<int>(0, (sum, c) => sum + (c.durationMs ?? 0));
    return Wrap(
      spacing: RevericSpacing.lg,
      runSpacing: RevericSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ScreenplayStatusItem(
          icon: RevericIcons.movie_outlined,
          label: context.t(
            LocaleKeys.productionStatusPlanned,
            namedArgs: {'seconds': '${(planned / 1000).round()}'},
          ),
        ),
        ScreenplayStatusItem(
          icon: RevericIcons.category_outlined,
          label: context.t(
            LocaleKeys.productionStatusCount,
            namedArgs: {
              'count': '${clips.length}',
              'scenes': '${scenes.length}',
            },
          ),
        ),
        ScreenplayStatusItem(
          icon: RevericIcons.checklist_rounded,
          label: context.t(
            LocaleKeys.productionStatusDone,
            namedArgs: {
              'done': '${clips.where((c) => c.adoptedAssetId != null).length}',
              'count': '${clips.length}',
            },
          ),
        ),
      ],
    );
  }
}
