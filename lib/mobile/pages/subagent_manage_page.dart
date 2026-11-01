// 职责: 移动端专家团 — 分开管理我的专家和官方专家，并进入编辑页修改（名称/描述/类型/模型/推理强度/提示词/启用）。
// 关联文件:
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/models/subagent.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/widgets/ai/reasoning_effort_bars.dart
//   lib/shared/services/ai/builtin_agent_tools.dart
//   lib/mobile/widgets/agent_edit_scaffold.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/agent_studio.json
//   assets/translations/zh-CN/agent_studio.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/state-management.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_switch.dart';
import '../../shared/components/reveric_text_field.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/models/ai_provider.dart';
import '../../shared/models/subagent.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/providers/subagent_providers.dart';
import '../../shared/services/ai/builtin_agent_tools.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/agent_avatar.dart';
import '../../shared/widgets/ai/reasoning_effort_bars.dart';
import '../../third/form/flutter_hook_form.dart';
import '../widgets/agent_edit_scaffold.dart';
import '../widgets/section_scaffold.dart';
import '../widgets/segmented_tab_switcher.dart';

final _log = AppLogger.forModule('MobileSubAgent');

Future<bool> _confirmAndDeleteSubAgent(
  BuildContext context,
  WidgetRef ref,
  SubAgent agent,
) async {
  final confirmed = await confirmAgentDelete(
    context,
    title: context.t(LocaleKeys.commonDelete),
    message: context.t(
      LocaleKeys.subagentDeleteConfirm,
      namedArgs: {'name': agent.name},
    ),
  );
  if (!confirmed) {
    return false;
  }

  try {
    await ref.read(globalSubAgentsProvider.notifier).deleteSubAgent(agent.id);
    return true;
  } catch (error, stack) {
    _log.error('delete failed', error: error, stackTrace: stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.commonDeleteFailed))),
      );
    }
    return false;
  }
}

/// 专家团列表页。
class MobileExpertTeamPage extends ConsumerWidget {
  const MobileExpertTeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(globalSubAgentsProvider);
    final agents = (agentsAsync.asData?.value ?? const <SubAgent>[])
        .where(isUserVisibleSubAgent)
        .toList(growable: false);
    final myExperts = agents
        .where((agent) => !builtinSubAgentSlugs.contains(agent.slug))
        .toList(growable: false);
    final officialExperts = agents
        .where(
          (agent) =>
              builtinSubAgentSlugs.contains(agent.slug) &&
              agent.mode == SubAgentMode.council.value,
        )
        .toList(growable: false);

    void openEdit(SubAgent agent) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _SubAgentEditPage(agent: agent),
        ),
      );
    }

    void create() {
      openEdit(
        SubAgent(
          id: '__new__${DateTime.now().microsecondsSinceEpoch}',
          slug: '',
          name: '',
          description: '',
          prompt: '',
          scope: SubAgentScope.global,
          sortOrder: myExperts.length,
        ),
      );
    }

    return MobileManageScaffold(
      title: context.t(LocaleKeys.agentStudioExpertTeam),
      onAdd: create,
      child: agentsAsync.isLoading && agents.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x4l,
                RevericSpacing.x2l,
                RevericSpacing.x4l,
                0,
              ),
              child: MobileSegmentedTabSwitcher(
                tabs: [
                  context.t(LocaleKeys.agentStudioMyExperts),
                  context.t(LocaleKeys.agentStudioOfficialExperts),
                ],
                children: [
                  _ExpertList(
                    experts: myExperts,
                    emptyHint: context.t(LocaleKeys.subagentEmpty),
                    onOpen: openEdit,
                    onDelete: (agent) =>
                        _confirmAndDeleteSubAgent(context, ref, agent),
                  ),
                  _ExpertList(
                    experts: officialExperts,
                    emptyHint: context.t(LocaleKeys.agentStudioExpertTeamEmpty),
                    onOpen: openEdit,
                    official: true,
                  ),
                ],
              ),
            ),
    );
  }
}

class _ExpertList extends StatelessWidget {
  const _ExpertList({
    required this.experts,
    required this.emptyHint,
    required this.onOpen,
    this.onDelete,
    this.official = false,
  });

  final List<SubAgent> experts;
  final String emptyHint;
  final ValueChanged<SubAgent> onOpen;
  final Future<bool> Function(SubAgent agent)? onDelete;
  final bool official;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    if (experts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x4l),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        top: RevericSpacing.md,
        bottom: RevericSpacing.x5l,
      ),
      itemCount: experts.length + (official ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: RevericSpacing.sm),
      itemBuilder: (context, index) {
        if (official && index == 0) {
          return _OfficialExpertsHint();
        }
        final agent = experts[index - (official ? 1 : 0)];
        return MobileSectionCard(
          cardKey: ValueKey('mobile_expert_card_${agent.id}'),
          onTap: () => onOpen(agent),
          onDelete: onDelete == null ? null : () => onDelete!(agent),
          deleteLabel: context.t(LocaleKeys.commonDelete),
          child: Row(
            children: [
              AgentAvatar(
                avatarPath: agent.avatarPath,
                slug: agent.slug,
                avatarEmoji: agent.avatarEmoji,
                size: 42,
                backgroundColor: colors.accent.withValues(alpha: 0.13),
              ),
              const SizedBox(width: RevericSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            agent.name.isEmpty
                                ? context.t(LocaleKeys.commonUntitled)
                                : agent.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typo.uiSemibold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        MobileSectionTagChip(
                          label: agent.mode == SubAgentMode.council.value
                              ? context.t(LocaleKeys.subagentModeCouncil)
                              : context.t(LocaleKeys.subagentModeChat),
                        ),
                        if (!agent.enabled) ...[
                          const SizedBox(width: RevericSpacing.xs),
                          MobileSectionTagChip(
                            label: context.t(LocaleKeys.agentRuleDisabled),
                            backgroundColor: colors.surfaceDim,
                            foregroundColor: colors.textSubtle,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.xs),
                    MobileSectionPreviewText(
                      preview: agent.description,
                      emptyPlaceholder: context.t(
                        LocaleKeys.subagentDescription,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              const MobileSectionTrailingChevron(),
            ],
          ),
        );
      },
    );
  }
}

class _OfficialExpertsHint extends StatelessWidget {
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

/// 子智能体编辑表单字段。
enum _Field implements FieldSchema {
  name(validators: [RequiredValidator<String>()]),
  description(),
  mode(),
  modelId(),
  reasoningEffort(),
  prompt(),
  useCustomPrompt(),
  enabled();

  const _Field({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class _SubAgentEditPage extends HookConsumerWidget {
  const _SubAgentEditPage({required this.agent});

  final SubAgent agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isNew = agent.id.startsWith('__new__');
    final isBuiltin = builtinSubAgentSlugs.contains(agent.slug);
    final initialModelId = agent.providerId != null && agent.model != null
        ? '${agent.providerId}::${agent.model}'
        : null;

    final form = useForm<_Field>(
      initialValues: {
        _Field.name: agent.name,
        _Field.description: agent.description,
        _Field.mode: SubAgentMode.fromString(agent.mode),
        _Field.modelId: initialModelId,
        _Field.reasoningEffort: agent.reasoningEffort,
        _Field.prompt: agent.prompt,
        _Field.useCustomPrompt: isBuiltin ? agent.useCustomPrompt : true,
        _Field.enabled: agent.enabled,
      },
      keys: [agent.id],
    );

    final nameCtrl = useTextEditingController(text: agent.name);
    final descCtrl = useTextEditingController(text: agent.description);
    final promptCtrl = useTextEditingController(text: agent.prompt);
    final saving = useState(false);
    final availableModels = ref.watch(availableAiModelsProvider);

    const disabledModelIds = <String>{};

    final useCustom = form.getValue<bool>(_Field.useCustomPrompt) ?? true;
    final promptEditable = !isBuiltin || useCustom;
    final modelId = form.getValue<String?>(_Field.modelId);
    final selectedOption = modelId == null
        ? null
        : availableModels.where((o) => o.id == modelId).firstOrNull;
    final selectedEffort = reasoningEffortForOption(
      selectedOption,
      form.getValue<String?>(_Field.reasoningEffort),
    );
    final showEffort =
        selectedOption != null &&
        (selectedOption.reasoningEfforts?.isNotEmpty ?? false);

    Future<void> save() async {
      if (!form.validate()) {
        return;
      }
      final name = nameCtrl.text.trim();
      final description = descCtrl.text.trim();
      final mode =
          (form.getValue<SubAgentMode>(_Field.mode) ?? SubAgentMode.chat).value;
      final modelId = form.getValue<String?>(_Field.modelId);
      final reasoningEffort = form.getValue<String?>(_Field.reasoningEffort);
      final enabled = form.getValue<bool>(_Field.enabled) ?? true;
      final customPrompt = isBuiltin
          ? (form.getValue<bool>(_Field.useCustomPrompt) ?? false)
          : true;
      final promptToSave = customPrompt ? promptCtrl.text.trim() : '';

      String? providerId;
      String? model;
      if (modelId != null && modelId.isNotEmpty) {
        final parts = modelId.split('::');
        if (parts.length == 2) {
          providerId = parts[0];
          model = parts[1];
        }
      }
      final option = modelId == null
          ? null
          : availableModels.where((o) => o.id == modelId).firstOrNull;
      final effortToSave = reasoningEffortForOption(option, reasoningEffort);

      saving.value = true;
      try {
        final notifier = ref.read(globalSubAgentsProvider.notifier);
        if (isNew) {
          await notifier.createSubAgent(
            SubAgentDraft(
              slug: _slugForNewExpert(name, agent.id),
              name: name,
              description: description,
              prompt: promptToSave,
              mode: mode,
              scope: SubAgentScope.global,
              useCustomPrompt: customPrompt,
              providerId: providerId,
              model: model,
              reasoningEffort: effortToSave,
            ),
          );
        } else {
          await notifier.updateSubAgent(
            agent.copyWith(
              name: name,
              description: description,
              prompt: promptToSave,
              mode: mode,
              enabled: enabled,
              useCustomPrompt: customPrompt,
              providerId: providerId,
              model: model,
              reasoningEffort: effortToSave,
            ),
          );
        }
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } on SubAgentNameConflictException {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t(
                  LocaleKeys.subagentDuplicateName,
                  namedArgs: {'name': name},
                ),
              ),
            ),
          );
        }
      } catch (error, stack) {
        _log.error('save failed', error: error, stackTrace: stack);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    return MobileAgentEditScaffold(
      title: isNew
          ? context.t(LocaleKeys.commonCreate)
          : (agent.name.isEmpty
                ? context.t(LocaleKeys.commonEdit)
                : agent.name),
      saving: saving.value,
      canSave: !saving.value,
      onSave: save,
      children: [
        HookedForm(
          form: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgentEditHero(
                icon: RevericIcons.smart_toy_outlined,
                emoji: isNew ? null : agent.avatarEmoji,
                avatarPath: isNew ? null : agent.avatarPath,
                avatarSlug: isNew ? null : agent.slug,
                title: isNew ? context.t(LocaleKeys.commonCreate) : agent.name,
                subtitle: context.t(LocaleKeys.commonEdit),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditEnableCard(
                value: form.getValue<bool>(_Field.enabled) ?? true,
                onChanged: (v) {
                  form.updateValue(_Field.enabled, v, notify: true);
                },
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentName),
                child: HookedFormField<_Field, String>(
                  fieldHook: _Field.name,
                  notifyOnChange: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.t(LocaleKeys.subagentNameRequired)
                      : null,
                  builder: (value, onChanged, error) => RevericTextField(
                    controller: nameCtrl,
                    autofocus: isNew,
                    errorText: error,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentDescription),
                child: HookedFormField<_Field, String>(
                  fieldHook: _Field.description,
                  notifyOnChange: true,
                  builder: (value, onChanged, error) => RevericTextField(
                    controller: descCtrl,
                    multiline: true,
                    minLines: 2,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    errorText: error,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentMode),
                child: HookedFormField<_Field, SubAgentMode>(
                  fieldHook: _Field.mode,
                  notifyOnChange: true,
                  builder: (value, onChanged, error) => _ModeSegmented(
                    value: value ?? SubAgentMode.chat,
                    onChanged: (m) => onChanged?.call(m),
                  ),
                ),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentModel),
                child: HookedFormField<_Field, String?>(
                  fieldHook: _Field.modelId,
                  notifyOnChange: true,
                  builder: (value, onChanged, error) => AgentModelField(
                    key: const ValueKey('mobile_expert_edit_model_field'),
                    modelLabel: mobileModelLabel(context, ref, value),
                    onTap: () async {
                      final picked = await showMobileModelPicker(
                        context,
                        ref,
                        selectedId: value,

                        disabledModelIds: disabledModelIds,
                      );
                      if (picked == null) {
                        return;
                      }
                      final nextId = picked.isEmpty ? null : picked;
                      onChanged?.call(nextId);
                      final option = nextId == null
                          ? null
                          : availableModels
                                .where((o) => o.id == nextId)
                                .firstOrNull;
                      form.updateValue(
                        _Field.reasoningEffort,
                        defaultEffortFor(option),
                        notify: true,
                      );
                    },
                  ),
                ),
              ),
              if (showEffort) ...[
                const SizedBox(height: RevericSpacing.x2l),
                AgentEditField(
                  label: context.t(LocaleKeys.aiReasoningEffort),
                  child: AgentEffortField(
                    effort: selectedEffort,
                    onTap: () async {
                      final efforts = selectedOption.reasoningEfforts!;
                      final picked = await showMobileEffortPicker(
                        context,
                        efforts: efforts,
                        selected: selectedEffort,
                      );
                      if (picked == null) {
                        return;
                      }
                      form.updateValue(
                        _Field.reasoningEffort,
                        picked,
                        notify: true,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentPrompt),
                trailing: isBuiltin
                    ? HookedFormField<_Field, bool>(
                        fieldHook: _Field.useCustomPrompt,
                        notifyOnChange: true,
                        builder: (value, onChanged, error) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t(LocaleKeys.subagentUseCustomPrompt),
                              style: typo.uiSmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.xs),
                            RevericSwitch(
                              value: value ?? false,
                              onChanged: (v) => onChanged?.call(v),
                            ),
                          ],
                        ),
                      )
                    : null,
                child: HookedFormField<_Field, String>(
                  fieldHook: _Field.prompt,
                  notifyOnChange: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) {
                    if (isBuiltin && !useCustom) {
                      return null;
                    }
                    return (value == null || value.trim().isEmpty)
                        ? context.t(LocaleKeys.subagentPromptRequired)
                        : null;
                  },
                  builder: (value, onChanged, error) => RevericTextField(
                    controller: promptCtrl,
                    multiline: true,
                    minLines: 6,
                    maxLines: 14,
                    readOnly: !promptEditable,
                    enabled: promptEditable,
                    keyboardType: TextInputType.multiline,
                    hintText: context.t(LocaleKeys.subagentPromptHint),
                    errorText: error,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 模式分段控件（对话 / 议会）。
class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.value, required this.onChanged});

  final SubAgentMode value;
  final ValueChanged<SubAgentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Widget option(SubAgentMode mode, String label, String icon) {
      final selected = mode == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: selected ? colors.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              border: Border.all(
                color: selected ? colors.accent : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RevericIcon(
                  icon,
                  size: 15,
                  color: selected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: Row(
        children: [
          option(
            SubAgentMode.chat,
            context.t(LocaleKeys.subagentModeChat),
            RevericIcons.chat_outlined,
          ),
          const SizedBox(width: 3),
          option(
            SubAgentMode.council,
            context.t(LocaleKeys.subagentModeCouncil),
            RevericIcons.groups_outlined,
          ),
        ],
      ),
    );
  }
}

String _slugForNewExpert(String name, String draftId) {
  final base = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final slugBase = base.isEmpty ? 'expert' : base;
  return '$slugBase-${draftId.replaceFirst('__new__', '')}';
}
