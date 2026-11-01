// 职责: AgentSkill 版本历史的跨端展示组件 — 版本列表项与只读详情（diff + 复制）。
// 关联文件:
//   lib/shared/models/agent_skill_revision.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/widgets/ai/diff/diff_view.dart
//   lib/desktop/features/agent_skills/skill_revision_history_panel.dart
//   lib/mobile/features/agent_skills/skill_revision_history_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/agent_skill_revision.dart';
import '../../models/novel_agent_skill.dart';
import '../../providers/novel_agent_skill_providers.dart';
import '../../theme/theme.dart';
import '../../utils/relative_time.dart';
import '../ai/diff/diff_view.dart';

/// 变更来源的展示文案 key。
String skillRevisionSourceLabelKey(SkillRevisionSource source) {
  return switch (source) {
    SkillRevisionSource.baseline => LocaleKeys.agentSkillHistorySourceBaseline,
    SkillRevisionSource.install => LocaleKeys.agentSkillHistorySourceInstall,
    SkillRevisionSource.user_edit => LocaleKeys.agentSkillHistorySourceUserEdit,
    SkillRevisionSource.ai_edit => LocaleKeys.agentSkillHistorySourceAiEdit,
    SkillRevisionSource.upgrade => LocaleKeys.agentSkillHistorySourceUpgrade,
  };
}

String _skillRevisionSourceIcon(SkillRevisionSource source) {
  return switch (source) {
    SkillRevisionSource.baseline => RevericIcons.clock,
    SkillRevisionSource.install => RevericIcons.arrow_circle_down_outlined,
    SkillRevisionSource.user_edit => RevericIcons.edit_outlined,
    SkillRevisionSource.ai_edit => RevericIcons.auto_awesome,
    SkillRevisionSource.upgrade => RevericIcons.git_fork,
  };
}

/// 单个版本的列表项。[isLatest] 时额外标注「当前版本」。
class SkillRevisionListTile extends StatelessWidget {
  const SkillRevisionListTile({
    super.key,
    required this.summary,
    required this.selected,
    required this.isLatest,
    required this.onTap,
  });

  final AgentSkillRevisionSummary summary;
  final bool selected;
  final bool isLatest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isAi = summary.changeSource == SkillRevisionSource.ai_edit;

    return Material(
      color: selected ? colors.surfaceContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RevericIcon(
                _skillRevisionSourceIcon(summary.changeSource),
                size: 16,
                color: isAi ? colors.accentWarm : colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'v${summary.revision}',
                          style: typo.uiMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        Flexible(
                          child: Text(
                            context.t(
                              skillRevisionSourceLabelKey(summary.changeSource),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typo.uiSmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (isLatest) ...[
                          const SizedBox(width: RevericSpacing.sm),
                          _Chip(
                            label: context.t(
                              LocaleKeys.agentSkillHistoryCurrent,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSmall.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    final time = formatRelativeTimeZh(summary.createdAt);
    final files = context.t(
      LocaleKeys.agentSkillHistoryFileCount,
      namedArgs: {'count': '${summary.fileCount}'},
    );
    final note = summary.changeNote?.trim() ?? '';
    return note.isEmpty ? '$time · $files' : '$time · $files · $note';
  }
}

/// 版本列表（空态自带）。
class SkillRevisionList extends StatelessWidget {
  const SkillRevisionList({
    super.key,
    required this.revisions,
    required this.selectedId,
    required this.onSelect,
  });

  final List<AgentSkillRevisionSummary> revisions;
  final String? selectedId;
  final ValueChanged<AgentSkillRevisionSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    if (revisions.isEmpty) {
      final colors = RevericTheme.colorsOf(context);
      final typo = RevericTheme.typographyOf(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          child: Text(
            context.t(LocaleKeys.agentSkillHistoryEmpty),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textSubtle),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: revisions.length,
      itemBuilder: (context, index) {
        final item = revisions[index];
        return SkillRevisionListTile(
          summary: item,
          selected: item.id == selectedId,
          isLatest: index == 0,
          onTap: () => onSelect(item),
        );
      },
    );
  }
}

/// 单个版本的只读详情：与当前技能的 prompt diff + 附件列表 + 复制动作。
///
/// 不提供恢复 —— 历史是 append-only 的留档，回退由用户参照内容自己改。
class SkillRevisionDetailView extends ConsumerWidget {
  const SkillRevisionDetailView({
    super.key,
    required this.revisionId,
    required this.current,
  });

  final String revisionId;
  final NovelAgentSkillModel current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final detailAsync = ref.watch(skillRevisionDetailProvider(revisionId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          child: Text(
            context.t(LocaleKeys.commonLoadFailed),
            style: typo.uiSmall.copyWith(color: colors.textSubtle),
          ),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Center(
            child: Text(
              context.t(LocaleKeys.agentSkillHistoryEmpty),
              style: typo.uiSmall.copyWith(color: colors.textSubtle),
            ),
          );
        }
        final promptChanged = detail.prompt != current.prompt;
        return ListView(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'v${detail.revision} · ${detail.name}',
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                ),
                _CopyButton(
                  label: context.t(LocaleKeys.agentSkillHistoryCopyPrompt),
                  value: detail.prompt,
                ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            _Field(
              label: context.t(LocaleKeys.agentSkillWhenToUse),
              value: detail.whenToUse,
            ),
            _Field(
              label: context.t(LocaleKeys.agentSkillDescription),
              value: detail.description,
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(LocaleKeys.agentSkillHistoryDiffTitle),
              style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            if (!promptChanged)
              Text(
                context.t(LocaleKeys.agentSkillHistoryNoPromptChange),
                style: typo.uiSmall.copyWith(color: colors.textSubtle),
              )
            else
              AiDiffView(oldText: detail.prompt, newText: current.prompt),
            if (detail.references.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.x2l),
              Text(
                context.t(LocaleKeys.agentSkillHistoryFiles),
                style: typo.uiSmallSemibold.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: RevericSpacing.sm),
              for (final reference in detail.references)
                Padding(
                  padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          reference.path,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiSmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      _CopyButton(
                        label: context.t(LocaleKeys.agentSkillHistoryCopyFile),
                        value: reference.content,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            trimmed,
            style: typo.uiSmall.copyWith(color: colors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final copied = context.t(LocaleKeys.agentSkillHistoryCopied);
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(copied)));
      },
      icon: const RevericIcon(RevericIcons.copy, size: 14),
      label: Text(label),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Text(label, style: typo.uiTiny.copyWith(color: colors.accent)),
    );
  }
}
