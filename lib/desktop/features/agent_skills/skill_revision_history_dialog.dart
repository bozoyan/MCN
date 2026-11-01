// 职责: 桌面端 AgentSkill 版本历史对话框 — 左列版本列表 + 右侧只读详情与 diff。
// 关联文件:
//   lib/shared/widgets/agent_skill/skill_revision_components.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/desktop/features/agent_skills/setup_edit_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/dialog_feedback.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_skill_revision.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_skill/skill_revision_components.dart';

/// 打开某个技能的版本历史对话框。只读，不提供恢复。
Future<void> showSkillRevisionHistoryDialog(
  BuildContext context, {
  required NovelAgentSkillModel skill,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => SkillRevisionHistoryDialog(skill: skill),
  );
}

class SkillRevisionHistoryDialog extends HookConsumerWidget {
  const SkillRevisionHistoryDialog({super.key, required this.skill});

  final NovelAgentSkillModel skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final selectedId = useState<String?>(null);
    final revisionsAsync = ref.watch(skillRevisionsProvider(skill.id));

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: DialogFeedback.intrinsic(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x3l,
                  RevericSpacing.x2l,
                  RevericSpacing.lg,
                  RevericSpacing.lg,
                ),
                child: Row(
                  children: [
                    RevericIcon(
                      RevericIcons.history_outlined,
                      size: 18,
                      color: colors.accent,
                    ),
                    const SizedBox(width: RevericSpacing.sm),
                    Expanded(
                      child: Text(
                        '${context.t(LocaleKeys.agentSkillHistory)} · ${skill.name}',
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.t(LocaleKeys.commonClose),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const RevericIcon(RevericIcons.close, size: 16),
                    ),
                  ],
                ),
              ),
              Divider(
                height: RevericSizes.dividerThickness,
                color: colors.border,
              ),
              Expanded(
                child: revisionsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(
                      context.t(LocaleKeys.commonLoadFailed),
                      style: typo.uiSmall.copyWith(color: colors.textSubtle),
                    ),
                  ),
                  data: (revisions) => _Body(
                    skill: skill,
                    revisions: revisions,
                    selectedId: selectedId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.skill,
    required this.revisions,
    required this.selectedId,
  });

  final NovelAgentSkillModel skill;
  final List<AgentSkillRevisionSummary> revisions;
  final ValueNotifier<String?> selectedId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    // 默认选中最新一条，避免右侧开局空白。
    final effectiveId =
        selectedId.value ?? (revisions.isEmpty ? null : revisions.first.id);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: SkillRevisionList(
            revisions: revisions,
            selectedId: effectiveId,
            onSelect: (item) => selectedId.value = item.id,
          ),
        ),
        VerticalDivider(
          width: RevericSizes.dividerThickness,
          thickness: RevericSizes.dividerThickness,
          color: colors.border,
        ),
        Expanded(
          child: effectiveId == null
              ? const SizedBox.shrink()
              : SkillRevisionDetailView(
                  revisionId: effectiveId,
                  current: skill,
                ),
        ),
      ],
    );
  }
}
