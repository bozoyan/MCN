// 职责: 移动端官方技能只读详情页 — 独立展示(非本地编辑页),含元信息、
//   使用条件/描述/指令与安装入口。
// 关联文件:
//   lib/mobile/features/agent_skills/official_tab.dart
//   lib/mobile/features/agent_skills/install_conflict_dialog.dart
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
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
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_skill_reference.dart';
import '../../../shared/models/catalog_skill_installation_state.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/providers/agent_skill_catalog_providers.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/providers/official_skill_sync_providers.dart';
import '../../../shared/models/official_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../../shared/widgets/promo_badge.dart';
import '../../widgets/section_scaffold.dart';
import 'install_conflict_dialog.dart';

/// 官方技能只读详情目标。
sealed class MobileCatalogSkillDetailTarget {
  const MobileCatalogSkillDetailTarget();
}

final class MobileOfficialSkillDetail extends MobileCatalogSkillDetailTarget {
  const MobileOfficialSkillDetail(this.skill);

  final OfficialAgentSkillSummary skill;
}

/// 官方技能只读详情页。
class CatalogSkillDetailPage extends ConsumerWidget {
  const CatalogSkillDetailPage({super.key, required this.target});

  final MobileCatalogSkillDetailTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (target) {
      MobileOfficialSkillDetail(:final skill) => _OfficialHost(
        listingId: skill.listingId,
        titleHint: skill.name,
      ),
    };
  }
}

class _OfficialHost extends ConsumerWidget {
  const _OfficialHost({required this.listingId, required this.titleHint});

  final String listingId;
  final String titleHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final asyncDetail = ref.watch(officialAgentSkillDetailProvider(listingId));

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(title: titleHint),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            Expanded(
              child: asyncDetail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _ErrorRetry(
                  message: context.t(LocaleKeys.agentSkillLoadFailed),
                  onRetry: () => ref.invalidate(
                    officialAgentSkillDetailProvider(listingId),
                  ),
                ),
                data: (detail) => _DetailBody(
                  view: _ViewData.fromOfficial(detail),
                  installSource: InstallFromOfficialSource(detail),
                  installLabelKey: LocaleKeys.agentSkillInstallFromOfficial,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewData {
  const _ViewData({
    required this.name,
    required this.whenToUse,
    required this.description,
    required this.prompt,
    required this.category,
    required this.tags,
    required this.references,
    required this.version,
    required this.badgeIcon,
    required this.sourceKind,
    required this.listingId,
    this.badgeLabel,
    required this.sourceLabelKey,
  });

  factory _ViewData.fromOfficial(OfficialAgentSkill skill) {
    return _ViewData(
      name: skill.name,
      whenToUse: skill.whenToUse,
      description: skill.description,
      prompt: skill.prompt,
      category: skill.category,
      tags: skill.tags,
      references: _toReferenceFiles(skill.references),
      version: skill.version,
      badgeIcon: RevericIcons.seal_check,
      sourceKind: AgentSkillSourceKind.official,
      listingId: skill.listingId,
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
  final AgentSkillSourceKind sourceKind;
  final String listingId;
  final String? badgeLabel;
  final String sourceLabelKey;
}

List<AgentSkillReferenceFile> _toReferenceFiles(
  List<AgentSkillReferenceFile> references,
) {
  return AgentSkillReferences.sanitize(references);
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.view,
    required this.installSource,
    required this.installLabelKey,
  });

  final _ViewData view;
  final InstallFromCatalogSource installSource;
  final String installLabelKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final installedSkills = ref
        .watch(installedAgentSkillsProvider)
        .whenOrNull(data: (skills) => skills);
    final installation = resolveCatalogSkillInstallationState(
      installedSkills: installedSkills,
      sourceKind: view.sourceKind,
      listingId: view.listingId,
      catalogName: view.name,
      catalogVersion: view.version,
    );
    // 官方安装与升级由启动同步负责；同步结束后开放手动操作，避免并发写入。
    // 市场技能不受官方同步状态限制。
    final isOfficial = view.sourceKind == AgentSkillSourceKind.official;
    final syncSettled = !ref.watch(officialSkillSyncProvider).isLoading;
    final showUpgrade = installation.canUpgrade && (!isOfficial || syncSettled);
    final looksInstalled =
        installation.isInstalled || (installation.canUpgrade && !showUpgrade);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x4l,
        RevericSpacing.x2l,
        RevericSpacing.x4l,
        RevericSpacing.x6l,
      ),
      children: [
        _Header(view: view),
        const SizedBox(height: RevericSpacing.x2l),
        FilledButton.icon(
          onPressed: installation.canInstall && (!isOfficial || syncSettled)
              ? () => resolveAndInstallCatalogSkill(
                  context,
                  ref,
                  source: installSource,
                )
              : showUpgrade
              ? () => upgradeCatalogSkillInstallations(
                  context,
                  ref,
                  novelAgentSkillIds: installation.staleInstallationIds,
                  latestVersion: view.version,
                )
              : null,
          icon: RevericIcon(
            showUpgrade
                ? RevericIcons.arrow_clockwise
                : looksInstalled
                ? RevericIcons.check
                : RevericIcons.download,
            size: 14,
          ),
          label: Text(
            context.t(
              showUpgrade
                  ? LocaleKeys.commonUpgradeNow
                  : looksInstalled
                  ? LocaleKeys.agentSkillDownloaded
                  : installLabelKey,
            ),
          ),
        ),
        const SizedBox(height: RevericSpacing.x3l),
        _SectionLabel(label: context.t(LocaleKeys.agentSkillWhenToUse)),
        const SizedBox(height: RevericSpacing.sm),
        _PlainBody(
          text: view.whenToUse,
          emptyFallback: context.t(LocaleKeys.commonNone),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _SectionLabel(label: context.t(LocaleKeys.agentSkillDescription)),
        const SizedBox(height: RevericSpacing.sm),
        _PlainBody(
          text: view.description,
          emptyFallback: context.t(LocaleKeys.commonNone),
        ),
        if (view.category.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x2l),
          _SectionLabel(label: context.t(LocaleKeys.agentSkillCategory)),
          const SizedBox(height: RevericSpacing.sm),
          MobileSectionTagChip(label: view.category),
        ],
        if (view.tags.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x2l),
          _SectionLabel(label: context.t(LocaleKeys.commonTags)),
          const SizedBox(height: RevericSpacing.sm),
          Wrap(
            spacing: RevericSpacing.xs,
            runSpacing: RevericSpacing.xxs,
            children: [
              for (final t in view.tags) MobileSectionTagChip(label: t),
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
          child: view.prompt.trim().isEmpty
              ? Text(
                  context.t(LocaleKeys.commonNone),
                  style: typo.uiSmall.copyWith(color: colors.textSubtle),
                )
              : RevericMarkdownPreview(data: view.prompt),
        ),
        if (view.references.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x2l),
          _SectionLabel(label: context.t(LocaleKeys.agentSkillReferences)),
          const SizedBox(height: RevericSpacing.sm),
          for (final reference in view.references) ...[
            _ReferenceCard(reference: reference),
            const SizedBox(height: RevericSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _ReferenceCard extends StatefulWidget {
  const _ReferenceCard({required this.reference});

  final AgentSkillReferenceFile reference;

  @override
  State<_ReferenceCard> createState() => _ReferenceCardState();
}

class _ReferenceCardState extends State<_ReferenceCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final reference = widget.reference;
    final hasContent = reference.content.trim().isNotEmpty;
    final fileName =
        reference.path.startsWith(AgentSkillReferences.relativeDirPrefix)
        ? reference.path.substring(
            AgentSkillReferences.relativeDirPrefix.length,
          )
        : reference.path;
    return InkWell(
      onTap: !hasContent
          ? null
          : () {
              setState(() => _isExpanded = !_isExpanded);
            },
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Container(
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
                if (hasContent)
                  RevericIcon(
                    _isExpanded
                        ? RevericIcons.expand_less_rounded
                        : RevericIcons.expand_more,
                    size: 16,
                    color: colors.textMuted,
                  ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: RevericSpacing.sm),
              RevericMarkdownPreview(data: reference.content),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view});

  final _ViewData view;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(RevericRadius.large),
              ),
              alignment: Alignment.center,
              child: RevericIcon(
                view.badgeIcon,
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
                    view.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typo.heading2.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t(view.sourceLabelKey),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            if (view.badgeLabel != null && view.badgeLabel!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: RevericSpacing.sm),
                child: RevericPromoBadge(
                  view.badgeLabel!.trim(),
                  compact: true,
                ),
              ),
            MobileSectionTagChip(
              label: context.t(
                LocaleKeys.agentSkillVersionLabel,
                namedArgs: {'version': '${view.version}'},
              ),
              backgroundColor: colors.accent.withValues(alpha: 0.12),
              foregroundColor: colors.accent,
            ),
          ],
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.xs,
        RevericSpacing.sm,
        RevericSpacing.lg,
        RevericSpacing.sm,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.sm),
              child: RevericIcon(
                RevericIcons.arrow_back,
                size: 22,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 38),
        ],
      ),
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
        height: 1.5,
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RevericSpacing.md),
            TextButton(
              onPressed: onRetry,
              child: Text(context.t(LocaleKeys.agentSkillRetry)),
            ),
          ],
        ),
      ),
    );
  }
}
