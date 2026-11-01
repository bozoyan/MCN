// 职责: 展示分集各场定稿状态与分镜采用数，并提供进入剧本入口。
// 关联文件:
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/providers/storyboard.dart
//   lib/shared/widgets/screenplay/scene_stage_cells.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../shared/database/novel_content_database.dart'
    show ProductionClipRow, ScreenplayEpisodeRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/storyboard.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/scene_stage_cells.dart';
import 'support.dart';

class MobileScreenplayEpisodeCard extends ConsumerWidget {
  const MobileScreenplayEpisodeCard({
    super.key,
    required this.path,
    required this.episode,
    required this.onTap,
    this.isCurrent = false,
    this.onDelete,
  });
  final String path;
  final ScreenplayEpisodeRow episode;
  final VoidCallback onTap;
  final bool isCurrent;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenes =
        ref.watch(screenplayScenesProvider(path, episode.id)).value ??
        const <ScreenplaySceneSummary>[];
    final clips =
        ref.watch(storyboardShotsProvider(path, episode.id)).value ??
        const <ProductionClipRow>[];
    final finals = scenes
        .where((scene) => scene.stage == screenplayStageFinal)
        .length;
    final adopted = clips.where((clip) => clip.adoptedAssetId != null).length;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final meta = typo.uiSmall.copyWith(color: colors.textMuted);
    final card = MobileScreenplayCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mobileEpisodeLabel(context, episode),
                  style: typo.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? colors.accentWarm : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              const RevericIcon(RevericIcons.chevron_right, size: 18),
            ],
          ),
          if (scenes.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.sm),
            ScreenplaySceneStageCells(scenes: scenes),
          ],
          const SizedBox(height: RevericSpacing.sm),
          Wrap(
            spacing: RevericSpacing.md,
            runSpacing: RevericSpacing.xs,
            children: [
              Text(
                context.t(
                  LocaleKeys.screenplaySceneCount,
                  namedArgs: {'count': '${scenes.length}'},
                ),
                style: meta,
              ),
              if (scenes.isNotEmpty)
                Text(
                  '${context.t(LocaleKeys.screenplayFinal)} $finals/${scenes.length}',
                  style: meta,
                ),
              if (clips.isNotEmpty)
                Text(
                  '${context.t(LocaleKeys.storyboardBoard)} $adopted/${clips.length}',
                  style: meta,
                ),
            ],
          ),
        ],
      ),
    );
    if (onDelete == null) {
      return card;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.26,
          children: [
            CustomSlidableAction(
              onPressed: (_) => onDelete!(),
              backgroundColor: colors.error.withValues(alpha: 0.88),
              borderRadius: BorderRadius.zero,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIcon(
                    RevericIcons.delete_outline,
                    size: 20,
                    color: colors.onAccent,
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    context.t(LocaleKeys.commonDelete),
                    style: typo.uiTiny.copyWith(color: colors.onAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        child: card,
      ),
    );
  }
}
