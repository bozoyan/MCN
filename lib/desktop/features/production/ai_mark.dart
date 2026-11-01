// 职责: 用小圆点标出仍可回退的 AI 片段改动；回退入口在聊天面板「最近改动」。
// 关联文件:
//   lib/shared/services/working_overlay.dart
//   lib/desktop/features/storyboard/shot_row.dart
//   lib/desktop/widgets/ai/diff/pending_changes_summary_card.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/working_overlay.dart';
import '../../../shared/theme/theme.dart';

/// AI 改动写入即生效，这里只说「AI 动过这一段」，不提供接受步骤。
/// 新增用 accentWarm、改写用 accent，与「最近改动」条目图标同色。
class ProductionAiMark extends ConsumerWidget {
  const ProductionAiMark({super.key, required this.path, required this.clipId});
  final String path;
  final String clipId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes =
        (ref.watch(workingChangesProvider(path)).value ?? <WorkingChange>[])
            .where(
              (c) =>
                  c.resourceType == 'production_clips' &&
                  c.resourceId == clipId &&
                  c.source == workingChangeSourceAi &&
                  c.status == workingChangeStatusActive,
            );
    if (changes.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    final created = changes.any((c) => c.changeType == 'create');
    return Tooltip(
      message: context.t(
        created ? LocaleKeys.productionAiNew : LocaleKeys.productionAiEdited,
      ),
      child: Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: RevericSpacing.xs),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: created ? colors.accentWarm : colors.accent,
        ),
      ),
    );
  }
}
