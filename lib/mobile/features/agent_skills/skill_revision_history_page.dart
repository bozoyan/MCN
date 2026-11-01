// 职责: 移动端 AgentSkill 版本历史页 — 单栏版本列表，点选进入只读详情与 diff。
// 关联文件:
//   lib/shared/widgets/agent_skill/skill_revision_components.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_skill/skill_revision_components.dart';

/// 版本历史列表页。只读，不提供恢复。
class SkillRevisionHistoryPage extends ConsumerWidget {
  const SkillRevisionHistoryPage({super.key, required this.skill});

  final NovelAgentSkillModel skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final revisionsAsync = ref.watch(skillRevisionsProvider(skill.id));

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: _appBar(
        context,
        colors: colors,
        typo: typo,
        title: context.t(LocaleKeys.agentSkillHistory),
      ),
      body: SafeArea(
        top: false,
        child: revisionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              context.t(LocaleKeys.commonLoadFailed),
              style: typo.uiSmall.copyWith(color: colors.textSubtle),
            ),
          ),
          data: (revisions) => SkillRevisionList(
            revisions: revisions,
            selectedId: null,
            onSelect: (item) {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => _SkillRevisionDetailPage(
                    skill: skill,
                    revisionId: item.id,
                    revision: item.revision,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SkillRevisionDetailPage extends StatelessWidget {
  const _SkillRevisionDetailPage({
    required this.skill,
    required this.revisionId,
    required this.revision,
  });

  final NovelAgentSkillModel skill;
  final String revisionId;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: _appBar(context, colors: colors, typo: typo, title: 'v$revision'),
      body: SafeArea(
        top: false,
        child: SkillRevisionDetailView(revisionId: revisionId, current: skill),
      ),
    );
  }
}

PreferredSizeWidget _appBar(
  BuildContext context, {
  required RevericColors colors,
  required RevericTypography typo,
  required String title,
}) {
  return AppBar(
    backgroundColor: colors.surface,
    foregroundColor: colors.textPrimary,
    title: Text(title, style: typo.uiSemibold),
    leading: IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: const RevericIcon(RevericIcons.arrow_back, size: 22),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
  );
}
