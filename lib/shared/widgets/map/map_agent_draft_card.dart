// 职责: 地图 Agent 草稿卡片 — 展示待审阅方案并提供显式应用或忽略入口。
// 关联文件:
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/shared/models/map_agent.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../components/reveric_surfaces.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/map_agent.dart';
import '../../theme/theme.dart';

class MapAgentDraftCard extends StatelessWidget {
  const MapAgentDraftCard({
    super.key,
    required this.draft,
    required this.onApply,
    required this.onDismiss,
  });

  final MapDesignDraft draft;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return RevericElevatedCard(
      key: const ValueKey('map_agent_draft_card'),
      fallback: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      borderColor: colors.accent.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.auto_awesome,
                size: 15,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.mapEditorAgentDraftTitle),
                  style: typo.uiSmallSemibold.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.mapEditorAgentDraftNote),
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            draft.prompt,
            key: const ValueKey('map_agent_draft_prompt'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSmall.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: RevericSpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: RevericSpacing.xs,
            runSpacing: RevericSpacing.xs,
            children: [
              TextButton(
                key: const ValueKey('map_agent_draft_dismiss'),
                onPressed: onDismiss,
                child: Text(context.t(LocaleKeys.mapEditorAgentDraftDismiss)),
              ),
              FilledButton(
                key: const ValueKey('map_agent_draft_apply'),
                onPressed: onApply,
                child: Text(context.t(LocaleKeys.mapEditorAgentDraftApply)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
