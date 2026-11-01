// 职责: Home 专家团页 — 分开展示内置议会专家与用户自定义专家，并支持模型覆写和启停。
// 关联文件:
//   lib/shared/providers/subagent_providers.dart
//   lib/desktop/widgets/agent_management/subagent_edit_panel.dart
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/agent_studio.json
//   assets/translations/zh-CN/agent_studio.json
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/components/reveric_switch.dart';
import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_more_menu_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/subagent.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/providers/subagent_providers.dart';
import '../../../shared/services/ai/builtin_agent_tools.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_avatar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../ai/model/model_selector.dart';
import 'home_management_cards.dart';

final _log = AppLogger.forModule('ExpertTeam');

enum _ExpertTab { mine, official }

class AgentExpertTeamPage extends HookConsumerWidget {
  const AgentExpertTeamPage({
    super.key,
    required this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    required this.onOpen,
    required this.onCreate,
  });

  final GlobalKey headerGestureExclusionKey;
  final double headerTrailingInset;
  final ValueChanged<SubAgent> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(globalSubAgentsProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final tab = useState(_ExpertTab.mine);
    final search = useDebouncedSearch();
    final options =
        settingsAsync.value?.aiSettings.availableModelOptions ??
        const <AiModelOption>[];

    return HomeManagementScaffold(
      headerGestureExclusionKey: headerGestureExclusionKey,
      headerTrailingInset: headerTrailingInset,
      icon: RevericIcons.groups_outlined,
      titleKey: LocaleKeys.agentStudioExpertTeam,
      createLabelKey: LocaleKeys.commonCreate,
      onCreate: onCreate,
      child: agentsAsync.when(
        loading: () => const HomeManagementLoadingState(),
        error: (_, _) => HomeManagementErrorState(
          message: context.t(LocaleKeys.commonLoadFailed),
        ),
        data: (agents) {
          final visible = agents
              .where(isUserVisibleSubAgent)
              .toList(growable: false);
          final official = visible
              .where(
                (agent) =>
                    builtinSubAgentSlugs.contains(agent.slug) &&
                    agent.mode == SubAgentMode.council.value,
              )
              .toList(growable: false);
          final mine = visible
              .where((agent) => !builtinSubAgentSlugs.contains(agent.slug))
              .toList(growable: false);
          final source = tab.value == _ExpertTab.mine ? mine : official;
          final query = search.query.trim().toLowerCase();
          final filtered = source
              .where(
                (agent) =>
                    query.isEmpty ||
                    agent.name.toLowerCase().contains(query) ||
                    agent.description.toLowerCase().contains(query),
              )
              .toList(growable: false);
          final actions = _ExpertActions(
            onOpen: onOpen,
            onToggleEnabled: (agent, enabled) =>
                _updateAgent(context, ref, agent.copyWith(enabled: enabled)),
            onModelChanged: (agent, optionId) =>
                _updateAgentModel(context, ref, agent, options, optionId),
            onResetPrompt: (agent) => _updateAgent(
              context,
              ref,
              agent.copyWith(useCustomPrompt: false, prompt: ''),
            ),
            onDelete: (agent) => _deleteAgent(context, ref, agent),
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.x2l,
                  RevericSpacing.x4l,
                  RevericSpacing.lg,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.t(LocaleKeys.agentStudioExpertTeamDescription),
                    style: RevericTheme.typographyOf(context).ui.copyWith(
                      color: RevericTheme.colorsOf(context).textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              _ExpertTabs(
                selected: tab.value,
                mineCount: mine.length,
                officialCount: official.length,
                onChanged: (next) => tab.value = next,
              ),
              Padding(
                padding: const EdgeInsets.all(RevericSpacing.x4l),
                child: RevericSearchField(
                  controller: search.controller,
                  hint: context.t(LocaleKeys.agentStudioSearchExperts),
                  height: RevericSizes.fieldHeight,
                ),
              ),
              Divider(height: RevericSizes.dividerThickness),
              Expanded(
                child: _ExpertList(
                  tab: tab.value,
                  experts: filtered,
                  options: options,
                  canSelectModel: settingsAsync.hasValue,
                  actions: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateAgent(
    BuildContext context,
    WidgetRef ref,
    SubAgent agent,
  ) async {
    try {
      await ref.read(globalSubAgentsProvider.notifier).updateSubAgent(agent);
    } catch (error, stackTrace) {
      _log.error(
        'update expert failed id=${agent.id}',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
        );
      }
    }
  }

  Future<void> _updateAgentModel(
    BuildContext context,
    WidgetRef ref,
    SubAgent agent,
    List<AiModelOption> options,
    String? optionId,
  ) async {
    AiModelOption? selected;
    for (final option in options) {
      if (option.id == optionId) {
        selected = option;
        break;
      }
    }
    await _updateAgent(
      context,
      ref,
      agent.copyWith(
        providerId: selected?.providerId,
        model: selected?.model,
        reasoningEffort: reasoningEffortForOption(
          selected,
          agent.reasoningEffort,
        ),
      ),
    );
  }

  Future<void> _deleteAgent(
    BuildContext context,
    WidgetRef ref,
    SubAgent agent,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.t(LocaleKeys.commonDelete),
      message: context.t(
        LocaleKeys.subagentDeleteConfirm,
        namedArgs: {'name': agent.name},
      ),
      confirmLabel: context.t(LocaleKeys.commonDelete),
      variant: ConfirmDialogVariant.error,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await ref.read(globalSubAgentsProvider.notifier).deleteSubAgent(agent.id);
    } catch (error, stackTrace) {
      _log.error(
        'delete expert failed id=${agent.id}',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.commonDeleteFailed))),
        );
      }
    }
  }
}

class _ExpertActions {
  const _ExpertActions({
    required this.onOpen,
    required this.onToggleEnabled,
    required this.onModelChanged,
    required this.onResetPrompt,
    required this.onDelete,
  });

  final ValueChanged<SubAgent> onOpen;
  final Future<void> Function(SubAgent agent, bool enabled) onToggleEnabled;
  final Future<void> Function(SubAgent agent, String? optionId) onModelChanged;
  final Future<void> Function(SubAgent agent) onResetPrompt;
  final Future<void> Function(SubAgent agent) onDelete;
}

class _ExpertTabs extends StatelessWidget {
  const _ExpertTabs({
    required this.selected,
    required this.mineCount,
    required this.officialCount,
    required this.onChanged,
  });

  final _ExpertTab selected;
  final int mineCount;
  final int officialCount;
  final ValueChanged<_ExpertTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Widget tabButton(_ExpertTab value, String label, int count) {
      final active = selected == value;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: RevericSpacing.xs),
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.xs,
              vertical: RevericSpacing.lg,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: active ? colors.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: (active ? typo.uiSemibold : typo.uiMedium).copyWith(
                    color: active ? colors.textPrimary : colors.textMuted,
                  ),
                ),
                const SizedBox(width: RevericSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? colors.accent.withValues(alpha: 0.16)
                        : colors.surfaceDim,
                    borderRadius: BorderRadius.circular(RevericRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: typo.uiTiny.copyWith(
                      color: active ? colors.accent : colors.textSubtle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: RevericSpacing.x5l,
        end: RevericSpacing.x5l,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          tabButton(
            _ExpertTab.mine,
            context.t(LocaleKeys.agentStudioMyExperts),
            mineCount,
          ),
          tabButton(
            _ExpertTab.official,
            context.t(LocaleKeys.agentStudioOfficialExperts),
            officialCount,
          ),
        ],
      ),
    );
  }
}

class _ExpertList extends StatelessWidget {
  const _ExpertList({
    required this.tab,
    required this.experts,
    required this.options,
    required this.canSelectModel,
    required this.actions,
  });

  final _ExpertTab tab;
  final List<SubAgent> experts;
  final List<AiModelOption> options;
  final bool canSelectModel;
  final _ExpertActions actions;

  @override
  Widget build(BuildContext context) {
    if (experts.isEmpty) {
      return const HomeManagementEmptyState(
        icon: RevericIcons.groups_outlined,
        emptyKey: LocaleKeys.agentStudioExpertTeamEmpty,
      );
    }

    final council = experts
        .where((agent) => agent.mode == SubAgentMode.council.value)
        .toList(growable: false);
    final execution = experts
        .where((agent) => agent.mode != SubAgentMode.council.value)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      children: [
        if (tab == _ExpertTab.official) ...[
          _OfficialExpertHint(),
          const SizedBox(height: RevericSpacing.x3l),
        ],
        _ExpertSection(
          title: context.t(LocaleKeys.agentStudioCouncilExperts),
          experts: council,
          options: options,
          canSelectModel: canSelectModel,
          actions: actions,
          official: tab == _ExpertTab.official,
        ),
        if (execution.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.x4l),
          _ExpertSection(
            title: context.t(LocaleKeys.agentStudioExecutionExperts),
            experts: execution,
            options: options,
            canSelectModel: canSelectModel,
            actions: actions,
            official: false,
          ),
        ],
      ],
    );
  }
}

class _OfficialExpertHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          RevericIcon(RevericIcons.info, size: 16, color: colors.accent),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.agentStudioOfficialExpertsHint),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpertSection extends StatelessWidget {
  const _ExpertSection({
    required this.title,
    required this.experts,
    required this.options,
    required this.canSelectModel,
    required this.actions,
    required this.official,
  });

  final String title;
  final List<SubAgent> experts;
  final List<AiModelOption> options;
  final bool canSelectModel;
  final _ExpertActions actions;
  final bool official;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    if (experts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              '· ${experts.length}',
              style: typo.uiTiny.copyWith(color: colors.textSubtle),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            mainAxisExtent: 250,
            crossAxisSpacing: RevericSpacing.x2l,
            mainAxisSpacing: RevericSpacing.x2l,
          ),
          itemCount: experts.length,
          itemBuilder: (context, index) {
            final expert = experts[index];
            return _ExpertCard(
              agent: expert,
              official: official,
              options: options,
              canSelectModel: canSelectModel,
              actions: actions,
            );
          },
        ),
      ],
    );
  }
}

class _ExpertCard extends StatelessWidget {
  const _ExpertCard({
    required this.agent,
    required this.official,
    required this.options,
    required this.canSelectModel,
    required this.actions,
  });

  final SubAgent agent;
  final bool official;
  final List<AiModelOption> options;
  final bool canSelectModel;
  final _ExpertActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final modelId = agent.providerId == null || agent.model == null
        ? null
        : '${agent.providerId}::${agent.model}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      child: InkWell(
        onTap: () => actions.onOpen(agent),
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        hoverColor: colors.hover,
        child: Container(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.xl),
            border: Border.all(color: colors.borderInput),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ExpertAvatar(agent: agent),
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.name,
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: RevericSpacing.xs),
                        _ExpertKindTag(agent: agent),
                      ],
                    ),
                  ),
                  RevericMoreMenuButton(
                    entries: () => [
                      RevericMenuItem(
                        icon: RevericIcons.edit_outlined,
                        iconColor: colors.textSecondary,
                        label: context.t(LocaleKeys.commonEdit),
                        onTap: () => actions.onOpen(agent),
                      ),
                      if (official)
                        RevericMenuItem(
                          icon: RevericIcons.arrow_counter_clockwise,
                          iconColor: colors.textSecondary,
                          label: context.t(LocaleKeys.commonReset),
                          onTap: () => unawaited(actions.onResetPrompt(agent)),
                        ),
                      if (!official) ...[
                        const RevericMenuDivider(),
                        RevericMenuItem(
                          icon: RevericIcons.delete_outline,
                          iconColor: colors.warningText,
                          labelColor: colors.warningText,
                          label: context.t(LocaleKeys.commonDelete),
                          onTap: () => unawaited(actions.onDelete(agent)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.lg),
              Expanded(
                child: Text(
                  agent.description,
                  style: typo.uiSmall.copyWith(
                    color: colors.textMuted,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: RevericSpacing.lg),
              Divider(height: RevericSizes.dividerThickness),
              const SizedBox(height: RevericSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: ModelSelector.field(
                      availableModels: options,
                      selectedId: modelId,
                      onChanged: (optionId) =>
                          unawaited(actions.onModelChanged(agent, optionId)),
                      placeholder: context.t(
                        LocaleKeys.subagentModelNotSelected,
                      ),
                      emptyMessage: context.t(
                        LocaleKeys.subagentNoModelsAvailable,
                      ),
                      dense: true,
                      enabled: canSelectModel,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  RevericSwitch(
                    value: agent.enabled,
                    onChanged: (enabled) =>
                        unawaited(actions.onToggleEnabled(agent, enabled)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpertAvatar extends StatelessWidget {
  const _ExpertAvatar({required this.agent});

  final SubAgent agent;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final council = agent.mode == SubAgentMode.council.value;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AgentAvatar(
          avatarPath: agent.avatarPath,
          slug: agent.slug,
          avatarEmoji: agent.avatarEmoji,
          size: 36,
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: council ? colors.accent : colors.textSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 2),
            ),
            child: RevericIcon(
              council ? RevericIcons.groups_outlined : RevericIcons.lightning,
              size: 9,
              color: colors.onAccent,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpertKindTag extends StatelessWidget {
  const _ExpertKindTag({required this.agent});

  final SubAgent agent;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final council = agent.mode == SubAgentMode.council.value;
    final label = council
        ? context.t(LocaleKeys.subagentModeCouncil)
        : context.t(LocaleKeys.subagentModeChat);
    final color = council ? colors.accent : colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Text(label, style: typo.uiTiny.copyWith(color: color)),
    );
  }
}
