// 职责: 移动端 AgentSkill Setup 的「官方目录」Tab — 类别筛选 + 列表 + 安装按钮。
//   watch officialAgentSkillsProvider,loading/error/empty/data 四态;类别 chips
//   从无 filter 列表去重;点击安装走 [resolveAndInstallCatalogSkill] 统一流程。
// 关联文件:
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/localization/app_localization.dart
//   lib/shared/theme/theme.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/mobile/features/agent_skills/install_conflict_dialog.dart
//   lib/mobile/features/agent_skills/tab_states.dart
//   lib/mobile/features/agent_skills/category_filter_bar.dart
//   lib/mobile/features/agent_skills/catalog_skill_detail_page.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/providers/async_read.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/agent_skill_catalog_providers.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/providers/official_skill_sync_providers.dart';
import '../../../shared/models/catalog_skill_installation_state.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/models/official_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/relative_time.dart';
import '../../../shared/widgets/promo_badge.dart';
import '../../widgets/section_scaffold.dart';
import 'catalog_skill_detail_page.dart';
import 'category_filter_bar.dart';
import 'install_conflict_dialog.dart';
import 'tab_states.dart';

/// 官方目录 Tab，展示本地打包的技能。
class OfficialAgentSkillTab extends HookConsumerWidget {
  const OfficialAgentSkillTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = useState<String?>(null);
    final processingListingId = useState<String?>(null);
    final filter = useMemoized(
      () => agentSkillCatalogFilter(category: selectedCategory.value),
      [selectedCategory.value],
    );
    final allOfficial = ref.watch(
      officialAgentSkillsProvider(agentSkillCatalogFilter()),
    );
    final categories = <String>{
      for (final skill in allOfficial.value?.agentSkills ?? const [])
        if (skill.category.isNotEmpty) skill.category,
    }.toList(growable: false)..sort();
    final asyncList = ref.watch(officialAgentSkillsProvider(filter));
    final installedSkillsAsync = ref.watch(installedAgentSkillsProvider);
    final installedSkills = installedSkillsAsync.whenOrNull(
      data: (skills) => skills,
    );
    if (installedSkillsAsync.hasError) {
      return SkillTabErrorRetry(
        message: context.t(LocaleKeys.agentSkillLoadFailed),
        onRetry: () => ref.invalidate(installedAgentSkillsProvider),
      );
    }

    // 官方安装与升级由启动同步负责；同步结束后开放手动操作，避免并发写入。
    // 同步期间保持已有安装状态，不闪出升级按钮。
    final syncSettled = !ref.watch(officialSkillSyncProvider).isLoading;

    return Column(
      children: [
        SkillCategoryFilterBar(
          categories: categories,
          selected: selectedCategory.value,
          onSelect: (next) => selectedCategory.value = next,
        ),
        Expanded(
          child: asyncList.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => SkillTabErrorRetry(
              message: context.t(LocaleKeys.agentSkillLoadFailed),
              onRetry: () => ref
                  .read(officialAgentSkillsProvider(filter).notifier)
                  .ensureFresh(force: true),
            ),
            data: (list) {
              final skills = list.agentSkills;
              if (skills.isEmpty) {
                return SkillTabEmptyState(
                  icon: RevericIcons.auto_awesome_outlined,
                  message: context.t(LocaleKeys.agentSkillOfficialEmpty),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.md,
                  RevericSpacing.x4l,
                  RevericSpacing.x5l,
                ),
                itemCount: skills.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: RevericSpacing.sm),
                itemBuilder: (context, index) {
                  final dto = skills[index];
                  final installation = resolveCatalogSkillInstallationState(
                    installedSkills: installedSkills,
                    sourceKind: AgentSkillSourceKind.official,
                    listingId: dto.listingId,
                    catalogName: dto.name,
                    catalogVersion: dto.version,
                  );
                  return _OfficialSkillCard(
                    dto: dto,
                    installation: installation,
                    isLoading: processingListingId.value == dto.listingId,
                    onOpenDetail: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CatalogSkillDetailPage(
                          target: MobileOfficialSkillDetail(dto),
                        ),
                      ),
                    ),
                    onInstall: !installation.canInstall || !syncSettled
                        ? null
                        : () => _runAction(
                            processingListingId,
                            dto.listingId,
                            () => _install(context, ref, dto),
                          ),
                    onUpgrade: !(installation.canUpgrade && syncSettled)
                        ? null
                        : () => _runAction(
                            processingListingId,
                            dto.listingId,
                            () => upgradeCatalogSkillInstallations(
                              context,
                              ref,
                              novelAgentSkillIds:
                                  installation.staleInstallationIds,
                              latestVersion: dto.version,
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _install(
    BuildContext context,
    WidgetRef ref,
    OfficialAgentSkillSummary dto,
  ) async {
    final detail = await ref.readFuture(
      officialAgentSkillDetailProvider(dto.listingId).future,
    );
    if (!context.mounted) {
      return;
    }
    await resolveAndInstallCatalogSkill(
      context,
      ref,
      source: InstallFromOfficialSource(detail),
    );
  }

  Future<void> _runAction(
    ValueNotifier<String?> processingListingId,
    String listingId,
    Future<void> Function() action,
  ) async {
    processingListingId.value = listingId;
    try {
      await action();
    } finally {
      processingListingId.value = null;
    }
  }
}

// ── 内部组件 ─────────────────────────────────────────────────────────────────

/// 顶部类别筛选条:水平滚动 chip 行,首项为「全部」。
/// 官方技能列表卡片 — 对齐 desktop SkSourceCard:
/// head(badge+title+version) / desc / meta(类别+tags) / foot(分割线+安装)。
class _OfficialSkillCard extends StatelessWidget {
  const _OfficialSkillCard({
    required this.dto,
    required this.installation,
    required this.onOpenDetail,
    this.isLoading = false,
    this.onInstall,
    this.onUpgrade,
  });

  final OfficialAgentSkillSummary dto;
  final CatalogSkillInstallationState installation;
  final VoidCallback onOpenDetail;
  final bool isLoading;
  final Future<void> Function()? onInstall;
  final Future<void> Function()? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final stamp = formatRelativeTimeFromIso(dto.updatedAt);
    return Material(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                    ),
                    child: RevericIcon(
                      RevericIcons.seal_check,
                      size: 17,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                  Expanded(
                    child: Text(
                      dto.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (dto.badge != null && dto.badge!.trim().isNotEmpty) ...[
                    const SizedBox(width: RevericSpacing.sm),
                    RevericPromoBadge(dto.badge!.trim(), compact: true),
                  ],
                  const SizedBox(width: RevericSpacing.sm),
                  MobileSectionTagChip(label: 'v${dto.version}'),
                ],
              ),
              const SizedBox(height: RevericSpacing.sm),
              MobileSectionPreviewText(
                preview: dto.description,
                emptyPlaceholder: context.t(LocaleKeys.agentSkillDescription),
              ),
              if (dto.category.isNotEmpty || dto.tags.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.xs),
                Wrap(
                  spacing: RevericSpacing.xs,
                  runSpacing: RevericSpacing.xxs,
                  children: [
                    if (dto.category.isNotEmpty)
                      MobileSectionTagChip(label: dto.category),
                    for (final t in dto.tags) MobileSectionTagChip(label: t),
                  ],
                ),
              ],
              const SizedBox(height: RevericSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: RevericSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: stamp.isEmpty
                            ? const SizedBox.shrink()
                            : Text(
                                context.t(
                                  LocaleKeys.agentSkillUpdatedAt,
                                  namedArgs: {'time': stamp},
                                ),
                                style: typo.uiTiny.copyWith(
                                  color: colors.textSubtle,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      if (onInstall != null ||
                          onUpgrade != null ||
                          installation.canInstall ||
                          installation.isInstalled ||
                          installation.canUpgrade ||
                          installation.status ==
                              CatalogSkillInstallationStatus.loading)
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : onUpgrade ?? onInstall,
                          icon: isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: colors.textMuted,
                                  ),
                                )
                              : RevericIcon(
                                  onUpgrade != null
                                      ? RevericIcons.arrow_clockwise
                                      : installation.isInstalled ||
                                            installation.canUpgrade
                                      ? RevericIcons.check
                                      : RevericIcons.download,
                                  size: 14,
                                ),
                          label: Text(
                            context.t(
                              onUpgrade != null
                                  ? LocaleKeys.commonUpgradeNow
                                  : installation.isInstalled ||
                                        installation.canUpgrade
                                  ? LocaleKeys.agentSkillDownloaded
                                  : LocaleKeys.agentSkillInstall,
                            ),
                          ),
                        ),
                    ],
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

// 空 / 错误态见 tab_states.dart(与广场 / 我的 tab 共用)。
