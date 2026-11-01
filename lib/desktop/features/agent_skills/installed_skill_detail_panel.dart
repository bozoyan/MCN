// 职责: 已安装技能详情 — 展示 official/marketplace 安装快照，并提供
//   「编辑」入口（编辑即脱离来源，转为本地技能）。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_panel.dart
//   lib/desktop/features/agent_skills/source_card.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../widgets/desktop_window_frame.dart';
import 'source_card.dart';

/// 已安装技能只读详情面板。
class InstalledSkillDetailPanel extends StatelessWidget {
  const InstalledSkillDetailPanel({
    super.key,
    required this.skill,
    required this.onBack,
    this.onEdit,
    this.headerTrailingInset = 0,
    this.headerGestureExclusionKey,
  });

  final NovelAgentSkillModel skill;
  final double headerTrailingInset;
  final GlobalKey? headerGestureExclusionKey;
  final VoidCallback onBack;

  /// 开始编辑。调用方负责先把技能转成本地快照再进编辑面板。
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final meta = _sourceMeta(skill.sourceKind);

    return Container(
      color: colors.canvas,
      child: Column(
        children: [
          Container(
            key: headerGestureExclusionKey,
            height: DesktopWindowFrame.titleBarHeight,
            color: colors.surfaceContainer,
            padding: EdgeInsets.only(
              left: RevericSpacing.x2l,
              right: RevericSpacing.x2l + headerTrailingInset,
            ),
            child: Row(
              children: [
                Tooltip(
                  message: MaterialLocalizations.of(context).backButtonTooltip,
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    hoverColor: colors.hover,
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.xs),
                      child: RevericIcon(
                        RevericIcons.chevron_left,
                        size: 18,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        context.t(meta.labelKey),
                        style: typo.ui.copyWith(color: colors.textMuted),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.xs,
                        ),
                        child: RevericIcon(
                          RevericIcons.chevron_right,
                          size: 14,
                          color: colors.textSubtle,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          skill.name,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  FilledButton(
                    onPressed: onEdit,
                    child: Text(context.t(LocaleKeys.commonEdit)),
                  ),
              ],
            ),
          ),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x6l,
                RevericSpacing.x4l,
                RevericSpacing.x6l,
                RevericSpacing.x6l,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(
                              RevericRadius.large,
                            ),
                          ),
                          child: RevericIcon(
                            meta.icon,
                            size: 28,
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
                                overflow: TextOverflow.ellipsis,
                                style: typo.display.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (skill.sourceVersion != null &&
                                  skill.sourceVersion!.isNotEmpty) ...[
                                const SizedBox(height: RevericSpacing.md),
                                AgentSkillSourceTag(
                                  icon: RevericIcons.git_fork,
                                  label: context.t(
                                    LocaleKeys.agentSkillVersionLabel,
                                    namedArgs: {
                                      'version': skill.sourceVersion!,
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.x3l),
                    _SectionLabel(
                      label: context.t(LocaleKeys.agentSkillWhenToUse),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    _BodyText(
                      text: skill.whenToUse,
                      emptyLabel: context.t(LocaleKeys.commonNone),
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    _SectionLabel(
                      label: context.t(LocaleKeys.agentSkillDescription),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    _BodyText(
                      text: skill.description,
                      emptyLabel: context.t(LocaleKeys.commonNone),
                    ),
                    if (skill.category.isNotEmpty) ...[
                      const SizedBox(height: RevericSpacing.x2l),
                      _SectionLabel(
                        label: context.t(LocaleKeys.agentSkillCategory),
                      ),
                      const SizedBox(height: RevericSpacing.sm),
                      AgentSkillSourceTag(
                        icon: RevericIcons.label_outline,
                        label: skill.category,
                      ),
                    ],
                    if (skill.tags.isNotEmpty) ...[
                      const SizedBox(height: RevericSpacing.x2l),
                      _SectionLabel(label: context.t(LocaleKeys.commonTags)),
                      const SizedBox(height: RevericSpacing.sm),
                      Wrap(
                        spacing: RevericSpacing.sm,
                        runSpacing: RevericSpacing.sm,
                        children: [
                          for (final tag in skill.tags)
                            AgentSkillSourceTag(label: tag),
                        ],
                      ),
                    ],
                    const SizedBox(height: RevericSpacing.x2l),
                    _SectionLabel(
                      label: context.t(LocaleKeys.agentSkillPrompt),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(RevericSpacing.x2l),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(
                          RevericRadius.large,
                        ),
                        border: Border.all(color: colors.borderInput),
                      ),
                      child: skill.prompt.trim().isEmpty
                          ? Text(
                              context.t(LocaleKeys.commonNone),
                              style: typo.uiSmall.copyWith(
                                color: colors.textSubtle,
                              ),
                            )
                          : RevericMarkdownPreview(
                              data: _promptForDetail(skill.prompt, skill.name),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _promptForDetail(String prompt, String skillName) {
  final lines = prompt.split('\n');
  final firstContentIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (firstContentIndex == -1) {
    return prompt;
  }

  final headingMatch = RegExp(
    r'^#{1,6}\s+(.+?)\s*$',
  ).firstMatch(lines[firstContentIndex].trim());
  if (headingMatch?.group(1)?.trim() != skillName.trim()) {
    return prompt;
  }

  lines.removeAt(firstContentIndex);
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return lines.join('\n');
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

class _BodyText extends StatelessWidget {
  const _BodyText({required this.text, required this.emptyLabel});

  final String text;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final trimmed = text.trim();
    return Text(
      trimmed.isEmpty ? emptyLabel : trimmed,
      style: typo.uiSmall.copyWith(
        color: trimmed.isEmpty ? colors.textSubtle : colors.textSecondary,
        height: 1.55,
      ),
    );
  }
}
