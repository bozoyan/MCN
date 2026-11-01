// 职责: 移动端已安装技能详情页 — official/marketplace 快照展示，并提供
//   「编辑」入口（编辑即脱离来源，转为本地技能）。
// 关联文件:
//   lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   lib/mobile/widgets/section_scaffold.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_skill_reference.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../widgets/section_scaffold.dart';

/// 已安装技能只读详情页。
class InstalledSkillDetailPage extends StatelessWidget {
  const InstalledSkillDetailPage({super.key, required this.skill, this.onEdit});

  final NovelAgentSkillModel skill;

  /// 开始编辑。调用方负责先把技能转成本地快照再进编辑页。
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final meta = _sourceMeta(skill.sourceKind);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.sm,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: RevericIcon(
                        RevericIcons.arrow_back,
                        size: 20,
                        color: colors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        skill.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (onEdit != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: RevericSpacing.sm,
                        ),
                        child: FilledButton(
                          onPressed: onEdit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(
                              horizontal: RevericSpacing.lg,
                            ),
                          ),
                          child: Text(context.t(LocaleKeys.commonEdit)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.x2l,
                  RevericSpacing.x4l,
                  RevericSpacing.x6l,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(
                            RevericRadius.large,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: RevericIcon(
                          meta.icon,
                          size: 22,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              skill.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: typo.heading2.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.t(meta.labelKey),
                              style: typo.uiSmall.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  Wrap(
                    spacing: RevericSpacing.xs,
                    runSpacing: RevericSpacing.xxs,
                    children: [
                      if (skill.sourceVersion != null &&
                          skill.sourceVersion!.isNotEmpty)
                        MobileSectionTagChip(
                          label: context.t(
                            LocaleKeys.agentSkillVersionLabel,
                            namedArgs: {'version': skill.sourceVersion!},
                          ),
                          backgroundColor: colors.accent.withValues(
                            alpha: 0.12,
                          ),
                          foregroundColor: colors.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.x3l),
                  _SectionLabel(
                    label: context.t(LocaleKeys.agentSkillWhenToUse),
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  _PlainBody(
                    text: skill.whenToUse,
                    emptyFallback: context.t(LocaleKeys.commonNone),
                  ),
                  const SizedBox(height: RevericSpacing.x2l),
                  _SectionLabel(
                    label: context.t(LocaleKeys.agentSkillDescription),
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  _PlainBody(
                    text: skill.description,
                    emptyFallback: context.t(LocaleKeys.commonNone),
                  ),
                  if (skill.category.isNotEmpty) ...[
                    const SizedBox(height: RevericSpacing.x2l),
                    _SectionLabel(
                      label: context.t(LocaleKeys.agentSkillCategory),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    MobileSectionTagChip(label: skill.category),
                  ],
                  if (skill.tags.isNotEmpty) ...[
                    const SizedBox(height: RevericSpacing.x2l),
                    _SectionLabel(label: context.t(LocaleKeys.commonTags)),
                    const SizedBox(height: RevericSpacing.sm),
                    Wrap(
                      spacing: RevericSpacing.xs,
                      runSpacing: RevericSpacing.xxs,
                      children: [
                        for (final t in skill.tags)
                          MobileSectionTagChip(label: t),
                      ],
                    ),
                  ],
                  const SizedBox(height: RevericSpacing.x2l),
                  _SectionLabel(label: context.t(LocaleKeys.agentSkillPrompt)),
                  const SizedBox(height: RevericSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(RevericSpacing.lg),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: skill.prompt.trim().isEmpty
                        ? Text(
                            context.t(LocaleKeys.commonNone),
                            style: typo.uiSmall.copyWith(
                              color: colors.textSubtle,
                            ),
                          )
                        : RevericMarkdownPreview(data: skill.prompt),
                  ),
                  if (skill.references.isNotEmpty) ...[
                    const SizedBox(height: RevericSpacing.x2l),
                    _SectionLabel(
                      label: context.t(LocaleKeys.agentSkillReferences),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    for (final ref in skill.references) ...[
                      _ReferenceCard(reference: ref),
                      const SizedBox(height: RevericSpacing.sm),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({String icon, String labelKey}) _sourceMeta(AgentSkillSourceKind kind) {
  return switch (kind) {
    AgentSkillSourceKind.official => (
      icon: RevericIcons.seal_check,
      labelKey: LocaleKeys.agentSkillSourceOfficial,
    ),
    AgentSkillSourceKind.marketplace => (
      icon: RevericIcons.storefront,
      labelKey: LocaleKeys.agentSkillSourceMarketplace,
    ),
    AgentSkillSourceKind.novelLocal => (
      icon: RevericIcons.edit_note_outlined,
      labelKey: LocaleKeys.agentSkillSourceNovelLocal,
    ),
  };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      label,
      style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
    );
  }
}

/// 只读参考文档卡片：文件名 + 内容（Markdown 预览）。
class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.reference});

  final AgentSkillReferenceFile reference;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final fileName =
        reference.path.startsWith(AgentSkillReferences.relativeDirPrefix)
        ? reference.path.substring(
            AgentSkillReferences.relativeDirPrefix.length,
          )
        : reference.path;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.description_outlined,
                size: 15,
                color: colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (reference.content.trim().isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.sm),
            RevericMarkdownPreview(data: reference.content),
          ],
        ],
      ),
    );
  }
}

class _PlainBody extends StatelessWidget {
  const _PlainBody({required this.text, required this.emptyFallback});

  final String text;
  final String emptyFallback;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final trimmed = text.trim();
    return Text(
      trimmed.isEmpty ? emptyFallback : trimmed,
      style: typo.uiSmall.copyWith(
        color: trimmed.isEmpty ? colors.textSubtle : colors.textSecondary,
        height: 1.55,
      ),
    );
  }
}
