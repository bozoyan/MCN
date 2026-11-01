// 职责: 官方目录 tab —— 展示本地打包的官方技能并以网格安装,支持 category/关键词过滤,
//   点击安装按钮调用 InstalledAgentSkillsNotifier.installFromOfficial,冲突时弹 InstallConflictDialog;
//   静默升级已结束仍落后时暴露手动升级入口。
// 关联文件:
//   lib/desktop/features/agent_skills/source_card.dart
//   lib/desktop/features/agent_skills/catalog_filter_bar.dart
//   lib/desktop/features/agent_skills/catalog_states.dart
//   lib/desktop/features/agent_skills/install_conflict_dialog.dart
//   lib/desktop/features/agent_skills/setup_panel.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/providers/async_read.dart';
import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/catalog_skill_installation_state.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/providers/agent_skill_catalog_providers.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/providers/official_skill_sync_providers.dart';
import '../../../shared/models/official_agent_skill.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/relative_time.dart';
import 'catalog_states.dart';
import 'source_card.dart';
import 'catalog_filter_bar.dart';
import 'install_conflict_dialog.dart';

/// 官方目录 tab。在 [SkillSetupPanel] 的 official tab 下渲染。
///
/// 目录技能安装到应用全局的 [InstalledAgentSkillsNotifier]。
/// 接收 [flash] 用于在安装成功/失败时复用父级 toast 通道。
/// [onOpenDetail] 打开整页只读详情。
class OfficialCatalogTab extends HookConsumerWidget {
  const OfficialCatalogTab({
    super.key,
    required this.flash,
    required this.onOpenDetail,
  });

  final void Function(String message) flash;
  final ValueChanged<OfficialAgentSkillSummary> onOpenDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catFilter = useState<String?>(null);
    final search = useDebouncedSearch();
    final installing = useState<String?>(null);
    final installedSkillsAsync = ref.watch(installedAgentSkillsProvider);
    final installedSkills = installedSkillsAsync.whenOrNull(
      data: (skills) => skills,
    );
    if (installedSkillsAsync.hasError) {
      return CatalogErrorState(
        onRetry: () => ref.invalidate(installedAgentSkillsProvider),
      );
    }

    // 官方安装与升级由启动同步负责；同步结束后开放手动操作，避免并发写入。
    // 同步期间保持已有安装状态，不闪出升级按钮。
    final syncSettled = !ref.watch(officialSkillSyncProvider).isLoading;
    bool showUpgrade(CatalogSkillInstallationState installation) =>
        installation.canUpgrade && syncSettled;

    // 官方目录的 filter.tag 按关键词解释（匹配 name/description/category/tags），
    // 搜索框文案是「搜索智能体技能」而非搜标签。
    final keyword = search.active ? search.query : null;
    // 无 filter 列表用于类别 chips，避免选中 category 后 chips 塌成一项。
    final allOfficial = ref.watch(
      officialAgentSkillsProvider(agentSkillCatalogFilter()),
    );
    final categories = <String>{
      for (final skill in allOfficial.value?.agentSkills ?? const [])
        if (skill.category.isNotEmpty) skill.category,
    }.toList(growable: false)..sort();
    final officialAsync = ref.watch(
      officialAgentSkillsProvider(
        agentSkillCatalogFilter(category: catFilter.value, tag: keyword),
      ),
    );

    return Column(
      children: [
        CatalogFilterBar(
          categories: categories,
          selectedCategory: catFilter.value,
          onCategory: (c) => catFilter.value = c,
          searchController: search.controller,
        ),
        Divider(
          height: RevericSizes.dividerThickness,
          color: RevericTheme.colorsOf(context).borderSubtle,
        ),
        Expanded(
          child: officialAsync.when(
            loading: () => const CatalogLoadingState(),
            error: (error, _) => CatalogErrorState(
              onRetry: () {
                final filter = agentSkillCatalogFilter(
                  category: catFilter.value,
                  tag: keyword,
                );
                ref
                    .read(officialAgentSkillsProvider(filter).notifier)
                    .ensureFresh(force: true);
              },
            ),
            data: (list) {
              if (list.agentSkills.isEmpty) {
                return CatalogEmptyState(
                  message: context.t(LocaleKeys.agentSkillOfficialEmpty),
                );
              }
              return AgentSkillSourceCardGrid(
                itemCount: list.agentSkills.length,
                itemBuilder: (context, index) {
                  final dto = list.agentSkills[index];
                  final stamp = formatRelativeTimeFromIso(dto.updatedAt);
                  final installation = resolveCatalogSkillInstallationState(
                    installedSkills: installedSkills,
                    sourceKind: AgentSkillSourceKind.official,
                    listingId: dto.listingId,
                    catalogName: dto.name,
                    catalogVersion: dto.version,
                  );
                  return AgentSkillSourceCard(
                    badgeIcon: RevericIcons.seal_check,
                    name: dto.name,
                    description: dto.description,
                    version: dto.version,
                    badgeLabel: dto.badge,
                    category: dto.category,
                    tags: dto.tags,
                    updatedAtLabel: stamp.isEmpty ? null : stamp,
                    onTap: () => onOpenDetail(dto),
                    primary: AgentSkillSourceCardPrimaryAction(
                      isLoading: installing.value == dto.listingId,
                      labelKey: showUpgrade(installation)
                          ? LocaleKeys.commonUpgradeNow
                          : installation.isInstalled || installation.canUpgrade
                          ? LocaleKeys.agentSkillDownloaded
                          : LocaleKeys.agentSkillInstall,
                      icon: showUpgrade(installation)
                          ? RevericIcons.arrow_clockwise
                          : installation.isInstalled || installation.canUpgrade
                          ? RevericIcons.check
                          : RevericIcons.download,
                      onPressed: installation.canInstall && syncSettled
                          ? () => _install(
                              context: context,
                              ref: ref,
                              dto: dto,
                              installing: installing,
                            )
                          : showUpgrade(installation)
                          ? () => _upgrade(
                              context: context,
                              ref: ref,
                              dto: dto,
                              installation: installation,
                              installing: installing,
                            )
                          : null,
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

  Future<void> _install({
    required BuildContext context,
    required WidgetRef ref,
    required OfficialAgentSkillSummary dto,
    required ValueNotifier<String?> installing,
  }) async {
    installing.value = dto.listingId;
    final installer = ref.read(installedAgentSkillsProvider.notifier);
    try {
      final detail = await ref.readFuture(
        officialAgentSkillDetailProvider(dto.listingId).future,
      );
      final result = await installer.installFromOfficial(source: detail);
      if (!context.mounted) {
        return;
      }
      switch (result) {
        case InstallFromCatalogSuccess():
          flash(
            context.t(
              LocaleKeys.agentSkillToastInstalled,
              namedArgs: {'name': dto.name},
            ),
          );
          ref.invalidate(installedAgentSkillsProvider);
        case InstallFromCatalogConflict(
          :final existingId,
          :final conflictingName,
        ):
          await _handleConflict(
            context: context,
            ref: ref,
            dto: detail,
            existingId: existingId,
            conflictingName: conflictingName,
          );
      }
    } catch (_) {
      // 不透出底层异常,UI 仅显示通用失败 toast。
      if (context.mounted) {
        flash(context.t(LocaleKeys.agentSkillLoadFailed));
      }
    } finally {
      if (context.mounted) {
        installing.value = null;
      }
    }
  }

  /// 静默升级已结束但技能仍落后时的手动补救入口。
  ///
  /// 与自动升级共用 [InstalledAgentSkillsNotifier.upgradeNovelAgentSkill]；
  /// 同名重装出的多个副本一起升。
  Future<void> _upgrade({
    required BuildContext context,
    required WidgetRef ref,
    required OfficialAgentSkillSummary dto,
    required CatalogSkillInstallationState installation,
    required ValueNotifier<String?> installing,
  }) async {
    if (installation.staleInstallationIds.isEmpty) {
      return;
    }
    installing.value = dto.listingId;
    final installer = ref.read(installedAgentSkillsProvider.notifier);
    try {
      var upgraded = false;
      for (final skillId in installation.staleInstallationIds) {
        final result = await installer.upgradeNovelAgentSkill(
          novelAgentSkillId: skillId,
        );
        if (result is UpgradeSuccess) {
          upgraded = true;
        }
      }
      if (!context.mounted) {
        return;
      }
      flash(
        upgraded
            ? context.t(
                LocaleKeys.agentSkillToastUpgraded,
                namedArgs: {'version': '${dto.version}'},
              )
            : context.t(LocaleKeys.agentSkillAlreadyLatest),
      );
    } catch (_) {
      if (context.mounted) {
        flash(context.t(LocaleKeys.agentSkillLoadFailed));
      }
    } finally {
      if (context.mounted) {
        installing.value = null;
      }
    }
  }

  Future<void> _handleConflict({
    required BuildContext context,
    required WidgetRef ref,
    required OfficialAgentSkill dto,
    required String existingId,
    required String conflictingName,
  }) async {
    final result = await showInstallConflictDialog(
      context,
      conflictingName: conflictingName,
      sourceName: dto.name,
    );
    if (!context.mounted) {
      return;
    }
    switch (result.action) {
      case InstallConflictAction.cancel:
        return;
      case InstallConflictAction.overwrite:
        try {
          await ref
              .read(installedAgentSkillsProvider.notifier)
              .overwriteInstall(
                existingNovelAgentSkillId: existingId,
                source: InstallFromOfficialSource(dto),
              );
          if (!context.mounted) {
            return;
          }
          flash(
            context.t(
              LocaleKeys.agentSkillToastOverwritten,
              namedArgs: {'name': dto.name},
            ),
          );
          ref.invalidate(installedAgentSkillsProvider);
        } catch (_) {
          if (context.mounted) {
            flash(context.t(LocaleKeys.agentSkillLoadFailed));
          }
        }
      case InstallConflictAction.rename:
        final newCall = result.newCallName;
        if (newCall == null) {
          return;
        }
        try {
          final retry = await ref
              .read(installedAgentSkillsProvider.notifier)
              .installFromOfficial(source: dto, overrideName: newCall);
          if (!context.mounted) {
            return;
          }
          if (retry case InstallFromCatalogSuccess()) {
            flash(
              context.t(
                LocaleKeys.agentSkillToastRenamed,
                namedArgs: {'call_name': newCall},
              ),
            );
            ref.invalidate(installedAgentSkillsProvider);
          } else if (retry case InstallFromCatalogConflict()) {
            flash(context.t(LocaleKeys.agentSkillCallNameTaken));
          }
        } catch (_) {
          if (context.mounted) {
            flash(context.t(LocaleKeys.agentSkillLoadFailed));
          }
        }
    }
  }
}
