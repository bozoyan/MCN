// 职责: 移动端地图工作台底部常驻条 — 浏览时是「制图师」入口 + 生成脚；出图中换成四阶段进度；
//       预览历史图时换成采用 / 重画。
// 关联文件:
//   lib/mobile/features/map/studio_page.dart
//   lib/shared/widgets/map/map_generate_footer.dart
//   lib/shared/providers/map_studio_controller.dart
//   lib/shared/services/generate_map_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/map_studio_controller.dart';
import '../../../shared/services/generate_map_orchestrator.dart';
import '../../../shared/theme/theme.dart';

class MobileMapBottomBar extends StatelessWidget {
  const MobileMapBottomBar({
    super.key,
    required this.phase,
    required this.stageIndex,
    required this.matchedCount,
    required this.candidateCount,
    required this.requiresPlaceRecognition,
    required this.onOpenDesigner,
    required this.footer,
    required this.onAdopt,
    required this.onRegenerate,
  });

  final MapStudioPhase phase;
  final int stageIndex;
  final int matchedCount;
  final int candidateCount;

  /// 预览的是历史图：采用时会按当前地点树重新识别地名。
  final bool requiresPlaceRecognition;
  final VoidCallback onOpenDesigner;

  /// 共享生成脚（预估、门禁、生成按钮），由页面按当前参数构建。
  final Widget footer;
  final VoidCallback onAdopt;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x2l,
            RevericSpacing.md,
            RevericSpacing.x2l,
            RevericSpacing.md,
          ),
          child: switch (phase) {
            MapStudioPhase.generating => _GeneratingProgress(
              stageIndex: stageIndex,
            ),
            MapStudioPhase.review => _ReviewActions(
              matchedCount: matchedCount,
              candidateCount: candidateCount,
              requiresPlaceRecognition: requiresPlaceRecognition,
              onAdopt: onAdopt,
              onRegenerate: onRegenerate,
            ),
            MapStudioPhase.viewing => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('mobile_map_open_designer'),
                    onPressed: onOpenDesigner,
                    icon: const RevericIcon(RevericIcons.explore, size: 15),
                    label: Text(context.t(LocaleKeys.mapEditorStudioTitle)),
                  ),
                ),
                const SizedBox(height: RevericSpacing.sm),
                footer,
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// 读地点 → 画地图 → 认地名 → 核对，四段进度条各自亮起。
class _GeneratingProgress extends StatelessWidget {
  const _GeneratingProgress({required this.stageIndex});

  final int stageIndex;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final labels = [
      context.t(LocaleKeys.mapEditorStudioStageRead),
      context.t(LocaleKeys.mapEditorStudioStageImage),
      context.t(LocaleKeys.mapEditorStudioStageLocate),
      context.t(LocaleKeys.mapEditorStudioStageVerify),
    ];
    final current = stageIndex.clamp(0, MapGenerationStage.values.length - 1);
    return Semantics(
      key: const ValueKey('mobile_map_generating_progress'),
      liveRegion: true,
      label: '${current + 1}/${labels.length} ${labels[current]}',
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Column(
                // 底栏拿到的是整屏高度的宽松约束，必须收紧，否则会把画布整个顶掉。
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: i == current
                          ? LinearProgressIndicator(
                              color: colors.accent,
                              backgroundColor: colors.borderSubtle,
                            )
                          : ColoredBox(
                              color: i < current
                                  ? colors.accent
                                  : colors.borderSubtle,
                            ),
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (i == current ? typo.uiTinySemibold : typo.uiTiny)
                        .copyWith(
                          color: i == current
                              ? colors.accent
                              : i < current
                              ? colors.textSecondary
                              : colors.textSubtle,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.matchedCount,
    required this.candidateCount,
    required this.requiresPlaceRecognition,
    required this.onAdopt,
    required this.onRegenerate,
  });

  final int matchedCount;
  final int candidateCount;
  final bool requiresPlaceRecognition;
  final VoidCallback onAdopt;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          requiresPlaceRecognition
              ? context.t(LocaleKeys.mapEditorStudioHistoryRecognizeOnApply)
              : context
                    .t(LocaleKeys.mapEditorStudioReviewNote)
                    .replaceFirst('{matched}', '$matchedCount')
                    .replaceFirst('{total}', '$candidateCount'),
          style: typo.uiTiny.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('mobile_map_regenerate'),
                onPressed: onRegenerate,
                icon: const RevericIcon(
                  RevericIcons.arrow_clockwise,
                  size: 14,
                ),
                label: Text(context.t(LocaleKeys.mapEditorStudioRegenerate)),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('mobile_map_adopt'),
                onPressed: onAdopt,
                icon: const RevericIcon(RevericIcons.check, size: 14),
                label: Text(context.t(LocaleKeys.mapEditorStudioAdopt)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
