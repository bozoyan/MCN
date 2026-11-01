// 职责: 官方技能整页只读详情 — 独立展示页(非本地编辑面板),左列文件列表
//   (SKILL.md 主体 + references)+ 右侧只读预览,含名称/类别/标签/使用条件/描述/
//   指令/参考文档与来源元信息。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_panel.dart
//   lib/desktop/features/agent_skills/agent_skill_reference_file_tree.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_skill_reference.dart';
import '../../../shared/providers/agent_skill_catalog_providers.dart';
import '../../../shared/models/official_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../../shared/widgets/promo_badge.dart';
import '../../widgets/desktop_window_frame.dart';
import 'agent_skill_reference_file_tree.dart';
import 'source_card.dart';

/// 技能目录只读详情目标。
sealed class AgentSkillCatalogDetailTarget {
  const AgentSkillCatalogDetailTarget();
}

/// 官方技能（目录仅含摘要，进入详情后按 listing_id 拉取全文）。
final class OfficialSkillCatalogDetail extends AgentSkillCatalogDetailTarget {
  const OfficialSkillCatalogDetail(this.skill);

  final OfficialAgentSkillSummary skill;
}

/// 官方技能整页只读详情。
class AgentSkillCatalogDetailPanel extends ConsumerWidget {
  const AgentSkillCatalogDetailPanel({
    super.key,
    required this.target,
    required this.onBack,
  });

  final AgentSkillCatalogDetailTarget target;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (target) {
      OfficialSkillCatalogDetail(:final skill) => _OfficialDetailHost(
        listingId: skill.listingId,
        titleHint: skill.name,
        onBack: onBack,
      ),
    };
  }
}

class _OfficialDetailHost extends ConsumerWidget {
  const _OfficialDetailHost({
    required this.listingId,
    required this.titleHint,
    required this.onBack,
  });

  final String listingId;
  final String titleHint;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final detailAsync = ref.watch(officialAgentSkillDetailProvider(listingId));

    return detailAsync.when(
      loading: () => _LoadingScaffold(onBack: onBack, titleHint: titleHint),
      error: (_, _) => _LoadingScaffold(
        onBack: onBack,
        titleHint: titleHint,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(LocaleKeys.agentSkillLoadFailed),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.md),
              TextButton(
                onPressed: () =>
                    ref.invalidate(officialAgentSkillDetailProvider(listingId)),
                child: Text(context.t(LocaleKeys.agentSkillRetry)),
              ),
            ],
          ),
        ),
      ),
      data: (detail) => _CatalogDetailView(
        onBack: onBack,
        view: _CatalogSkillViewData.fromOfficial(detail),
      ),
    );
  }
}

class _CatalogSkillViewData {
  const _CatalogSkillViewData({
    required this.name,
    required this.whenToUse,
    required this.description,
    required this.prompt,
    required this.category,
    required this.tags,
    required this.references,
    required this.version,
    required this.badgeIcon,
    this.badgeLabel,
    required this.sourceLabelKey,
  });

  factory _CatalogSkillViewData.fromOfficial(OfficialAgentSkill skill) {
    return _CatalogSkillViewData(
      name: skill.name,
      whenToUse: skill.whenToUse,
      description: skill.description,
      prompt: skill.prompt,
      category: skill.category,
      tags: skill.tags,
      references: _toReferenceFiles(skill.references),
      version: skill.version,
      badgeIcon: RevericIcons.seal_check,
      badgeLabel: skill.badge,
      sourceLabelKey: LocaleKeys.agentSkillSourceOfficial,
    );
  }

  final String name;
  final String whenToUse;
  final String description;
  final String prompt;
  final String category;
  final List<String> tags;
  final List<AgentSkillReferenceFile> references;
  final int version;
  final String badgeIcon;
  final String? badgeLabel;
  final String sourceLabelKey;
}

/// 校验目录附件，丢弃非法项。
List<AgentSkillReferenceFile> _toReferenceFiles(
  List<AgentSkillReferenceFile> dtos,
) {
  return AgentSkillReferences.sanitize(dtos);
}

class _CatalogDetailView extends StatefulWidget {
  const _CatalogDetailView({required this.onBack, required this.view});

  final VoidCallback onBack;
  final _CatalogSkillViewData view;

  @override
  State<_CatalogDetailView> createState() => _CatalogDetailViewState();
}

class _CatalogDetailViewState extends State<_CatalogDetailView> {
  /// -1 = SKILL.md 主体；>=0 = references 下标。
  int _selection = -1;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final view = widget.view;
    final refs = view.references;
    final selectedIndex = _selection >= 0 && _selection < refs.length
        ? _selection
        : -1;

    return Container(
      color: colors.canvas,
      child: Column(
        children: [
          _DetailHeader(title: view.name, onBack: widget.onBack),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgentSkillReferenceFileTree(
                  references: refs,
                  selectedIndex: selectedIndex,
                  readOnly: true,
                  onSelectMain: () => setState(() => _selection = -1),
                  onSelectReference: (i) => setState(() => _selection = i),
                ),
                VerticalDivider(
                  width: RevericSizes.dividerThickness,
                  thickness: RevericSizes.dividerThickness,
                  color: colors.border,
                ),
                Expanded(
                  child: IndexedStack(
                    index: selectedIndex == -1 ? 0 : 1,
                    sizing: StackFit.expand,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          RevericSpacing.x6l,
                          RevericSpacing.x4l,
                          RevericSpacing.x6l,
                          RevericSpacing.x6l,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 840),
                          child: _CatalogMainContent(view: view),
                        ),
                      ),
                      selectedIndex == -1
                          ? const SizedBox.shrink()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                RevericSpacing.x6l,
                                RevericSpacing.x4l,
                                RevericSpacing.x6l,
                                RevericSpacing.x6l,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 840,
                                ),
                                child: _ReferencePreview(
                                  reference: refs[selectedIndex],
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 只读详情主体：intro + 各字段 + 指令预览。
class _CatalogMainContent extends StatelessWidget {
  const _CatalogMainContent({required this.view});

  final _CatalogSkillViewData view;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailIntro(view: view),
        const SizedBox(height: RevericSpacing.x3l),
        _SectionLabel(label: context.t(LocaleKeys.agentSkillWhenToUse)),
        const SizedBox(height: RevericSpacing.sm),
        _BodyText(
          text: view.whenToUse,
          emptyLabel: context.t(LocaleKeys.commonNone),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _SectionLabel(label: context.t(LocaleKeys.agentSkillDescription)),
        const SizedBox(height: RevericSpacing.sm),
        _BodyText(
          text: view.description,
          emptyLabel: context.t(LocaleKeys.commonNone),
        ),
        if (view.category.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x2l),
          _SectionLabel(label: context.t(LocaleKeys.agentSkillCategory)),
          const SizedBox(height: RevericSpacing.sm),
          AgentSkillSourceTag(
            icon: RevericIcons.label_outline,
            label: view.category,
          ),
        ],
        if (view.tags.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x2l),
          _SectionLabel(label: context.t(LocaleKeys.commonTags)),
          const SizedBox(height: RevericSpacing.sm),
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: [
              for (final tag in view.tags) AgentSkillSourceTag(label: tag),
            ],
          ),
        ],
        const SizedBox(height: RevericSpacing.x2l),
        _SectionLabel(label: context.t(LocaleKeys.agentSkillPrompt)),
        const SizedBox(height: RevericSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput),
          ),
          child: view.prompt.trim().isEmpty
              ? Text(
                  context.t(LocaleKeys.commonNone),
                  style: typo.uiSmall.copyWith(color: colors.textSubtle),
                )
              : RevericMarkdownPreview(data: view.prompt, showCopyButton: true),
        ),
      ],
    );
  }
}

/// 只读引用预览：文件名 + 内容（Markdown 预览）。
class _ReferencePreview extends StatelessWidget {
  const _ReferencePreview({required this.reference});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fileName,
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput),
          ),
          child: reference.content.trim().isEmpty
              ? Text(
                  context.t(LocaleKeys.commonNone),
                  style: typo.uiSmall.copyWith(color: colors.textSubtle),
                )
              : RevericMarkdownPreview(
                  data: reference.content,
                  showCopyButton: true,
                ),
        ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      height: DesktopWindowFrame.titleBarHeight,
      color: colors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const RevericIcon(RevericIcons.arrow_back, size: 16),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailIntro extends StatelessWidget {
  const _DetailIntro({required this.view});

  final _CatalogSkillViewData view;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(RevericRadius.large),
          ),
          child: RevericIcon(view.badgeIcon, size: 28, color: colors.accent),
        ),
        const SizedBox(width: RevericSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                view.name,
                overflow: TextOverflow.ellipsis,
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                context.t(view.sourceLabelKey),
                style: typo.bodySmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.md),
              Wrap(
                spacing: RevericSpacing.sm,
                runSpacing: RevericSpacing.sm,
                children: [
                  if (view.badgeLabel != null &&
                      view.badgeLabel!.trim().isNotEmpty)
                    RevericPromoBadge(view.badgeLabel!.trim()),
                  AgentSkillSourceTag(
                    icon: RevericIcons.git_fork,
                    label: context.t(
                      LocaleKeys.agentSkillVersionLabel,
                      namedArgs: {'version': '${view.version}'},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
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

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({required this.onBack, this.titleHint, this.child});

  final VoidCallback onBack;
  final String? titleHint;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      color: colors.canvas,
      child: Column(
        children: [
          Container(
            height: DesktopWindowFrame.titleBarHeight,
            color: colors.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const RevericIcon(RevericIcons.arrow_back, size: 16),
                ),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    titleHint ??
                        context.t(LocaleKeys.agentSkillSourceMarketplace),
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: child ?? const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
