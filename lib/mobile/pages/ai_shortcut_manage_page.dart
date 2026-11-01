// 职责: 移动端「快捷方式」管理 — 列出全局 AI 快捷方式并进入编辑页增删改（名称/提示词/适用位置/自动发送/启用，内置可恢复默认）。
// 关联文件:
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/models/ai_shortcut_action.dart
//   lib/mobile/widgets/agent_edit_scaffold.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
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
import '../../shared/models/ai_shortcut_action.dart';
import '../../shared/providers/ai_shortcut_action_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../third/form/flutter_hook_form.dart';
import '../widgets/agent_edit_scaffold.dart';
import '../widgets/section_scaffold.dart';

final _log = AppLogger.forModule('MobileAiShortcut');

Future<bool> _confirmAndDeleteShortcut(
  BuildContext context,
  WidgetRef ref,
  AiShortcutActionDefinition action,
) async {
  if (action.isBuiltin) {
    return false;
  }
  final confirmed = await confirmAgentDelete(
    context,
    title: context.t(LocaleKeys.commonDelete),
    message: context.t(
      LocaleKeys.agentShortcutDeleteConfirm,
      namedArgs: {'name': action.name},
    ),
  );
  if (!confirmed) {
    return false;
  }

  try {
    await ref.read(aiShortcutActionsProvider.notifier).deleteAction(action.id);
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

/// 「快捷方式」管理列表页。
class MobileAiShortcutManagePage extends ConsumerWidget {
  const MobileAiShortcutManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final actionsAsync = ref.watch(aiShortcutActionsProvider);
    final actions =
        actionsAsync.asData?.value ?? const <AiShortcutActionDefinition>[];

    void openEdit(AiShortcutActionDefinition action) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ShortcutEditPage(action: action),
        ),
      );
    }

    void create() {
      openEdit(
        AiShortcutActionDefinition(
          id: '__new__${DateTime.now().microsecondsSinceEpoch}',
          name: '',
          prompt: '',
          locations: const [],
        ),
      );
    }

    return MobileManageScaffold(
      title: context.t(LocaleKeys.agentShortcutTitle),
      onAdd: create,
      child: actionsAsync.isLoading && actions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : MobileSectionListScaffold(
              showCreateBar: false,
              createLabel: context.t(LocaleKeys.commonCreate),
              onCreate: create,
              emptyIcon: RevericIcons.rocket_launch_outlined,
              emptySectionLabel: context.t(LocaleKeys.agentShortcutTitle),
              emptyHint: context.t(LocaleKeys.agentShortcutEmpty),
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final action = actions[index];
                return MobileSectionCard(
                  onTap: () => openEdit(action),
                  onDelete: action.isBuiltin
                      ? null
                      : () => _confirmAndDeleteShortcut(context, ref, action),
                  deleteLabel: action.isBuiltin
                      ? null
                      : context.t(LocaleKeys.commonDelete),
                  child: Row(
                    children: [
                      MobileSectionIconBox(
                        icon: RevericIcons.rocket_launch_outlined,
                        size: 42,
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
                                    action.name.isEmpty
                                        ? context.t(LocaleKeys.commonUntitled)
                                        : action.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: RevericTheme.typographyOf(context)
                                        .uiSemibold
                                        .copyWith(color: colors.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: RevericSpacing.sm),
                                MobileSectionTagChip(
                                  label: action.isBuiltin
                                      ? context.t(
                                          LocaleKeys.agentShortcutBuiltin,
                                        )
                                      : context.t(
                                          LocaleKeys.agentShortcutCustom,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: RevericSpacing.xs),
                            MobileSectionPreviewText(
                              preview: action.prompt,
                              emptyPlaceholder: context.t(
                                LocaleKeys.agentShortcutPrompt,
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
            ),
    );
  }
}

enum _Field implements FieldSchema {
  name(validators: [RequiredValidator<String>()]),
  prompt(validators: [RequiredValidator<String>()]),
  locations(),
  autoSend(),
  enabled();

  const _Field({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class _ShortcutEditPage extends HookConsumerWidget {
  const _ShortcutEditPage({required this.action});

  final AiShortcutActionDefinition action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isNew = action.id.startsWith('__new__');

    final form = useForm<_Field>(
      initialValues: {
        _Field.name: action.name,
        _Field.prompt: action.prompt,
        _Field.locations: action.locations,
        _Field.autoSend: action.autoSend,
        _Field.enabled: action.enabled,
      },
      keys: [action.id],
    );

    final nameCtrl = useTextEditingController(text: action.name);
    final promptCtrl = useTextEditingController(text: action.prompt);
    final saving = useState(false);

    Future<void> save() async {
      if (!form.validate()) {
        return;
      }
      final locations =
          form.getValue<List<AiShortcutActionLocation>>(_Field.locations) ??
          const <AiShortcutActionLocation>[];
      if (locations.isEmpty) {
        form.setError(
          _Field.locations,
          context.t(LocaleKeys.agentShortcutLocationsRequired),
        );
        return;
      }

      saving.value = true;
      try {
        final notifier = ref.read(aiShortcutActionsProvider.notifier);
        final name = nameCtrl.text.trim();
        final prompt = promptCtrl.text.trim();
        final autoSend = form.getValue<bool>(_Field.autoSend) ?? false;
        final enabled = form.getValue<bool>(_Field.enabled) ?? true;

        if (isNew) {
          await notifier.createAction(
            AiShortcutActionDraft(
              name: name,
              prompt: prompt,
              locations: locations,
              enabled: enabled,
              autoSend: autoSend,
            ),
          );
        } else {
          await notifier.updateAction(
            action.copyWith(
              name: name,
              prompt: prompt,
              locations: locations,
              enabled: enabled,
              autoSend: autoSend,
            ),
          );
        }
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } on AiShortcutActionNameConflictException catch (e) {
        if (context.mounted) {
          form.setError(
            _Field.name,
            context.t(
              LocaleKeys.agentShortcutDuplicateName,
              namedArgs: {'name': e.name},
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

    Future<void> restoreDefault() async {
      final builtinId = action.builtinId;
      if (builtinId == null || builtinId.isEmpty) {
        return;
      }
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.agentShortcutRestoreDefault),
        message: context.t(
          LocaleKeys.agentShortcutRestoreDefaultConfirm,
          namedArgs: {'name': action.name},
        ),
        confirmLabel: context.t(LocaleKeys.agentShortcutRestoreDefault),
      );
      if (!confirmed) {
        return;
      }
      await ref
          .read(aiShortcutActionsProvider.notifier)
          .restoreBuiltin(builtinId);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    return MobileAgentEditScaffold(
      title: isNew
          ? context.t(LocaleKeys.commonCreate)
          : (action.name.isEmpty
                ? context.t(LocaleKeys.commonEdit)
                : action.name),
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
                icon: RevericIcons.rocket_launch_outlined,
                title: isNew ? context.t(LocaleKeys.commonCreate) : action.name,
                subtitle: action.isBuiltin
                    ? context.t(LocaleKeys.agentShortcutBuiltin)
                    : context.t(LocaleKeys.agentShortcutCustom),
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
                label: context.t(LocaleKeys.agentShortcutName),
                child: HookedFormField<_Field, String>(
                  fieldHook: _Field.name,
                  notifyOnChange: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.t(LocaleKeys.agentShortcutNameRequired)
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
                label: context.t(LocaleKeys.agentShortcutApplicableLocations),
                child: HookedFormField<_Field, List<AiShortcutActionLocation>>(
                  fieldHook: _Field.locations,
                  builder: (value, onChanged, error) => _LocationSelector(
                    selected: value ?? const <AiShortcutActionLocation>[],
                    errorText: error,
                    onChanged: (next) => onChanged?.call(next),
                  ),
                ),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.lg,
                  vertical: RevericSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(RevericRadius.large),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t(LocaleKeys.agentShortcutAutoSend),
                        style: typo.uiMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    HookedFormField<_Field, bool>(
                      fieldHook: _Field.autoSend,
                      notifyOnChange: true,
                      builder: (value, onChanged, error) => RevericSwitch(
                        value: value ?? false,
                        onChanged: (v) => onChanged?.call(v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.agentShortcutPrompt),
                child: HookedFormField<_Field, String>(
                  fieldHook: _Field.prompt,
                  notifyOnChange: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.t(LocaleKeys.agentShortcutPromptRequired)
                      : null,
                  builder: (value, onChanged, error) => RevericTextField(
                    controller: promptCtrl,
                    multiline: true,
                    minLines: 6,
                    maxLines: 14,
                    keyboardType: TextInputType.multiline,
                    hintText: context.t(LocaleKeys.agentShortcutPromptHint),
                    errorText: error,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ),
              if (action.isBuiltin) ...[
                const SizedBox(height: RevericSpacing.x3l),
                OutlinedButton.icon(
                  onPressed: restoreDefault,
                  icon: const RevericIcon(
                    RevericIcons.history_outlined,
                    size: 16,
                  ),
                  label: Text(
                    context.t(LocaleKeys.agentShortcutRestoreDefault),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 适用位置多选（FilterChip）。
class _LocationSelector extends StatelessWidget {
  const _LocationSelector({
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final List<AiShortcutActionLocation> selected;
  final ValueChanged<List<AiShortcutActionLocation>> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final selectedSet = selected.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: RevericSpacing.sm,
          runSpacing: RevericSpacing.sm,
          children: [
            for (final location in AiShortcutActionLocation.values)
              FilterChip(
                selected: selectedSet.contains(location),
                label: Text(_locationLabel(context, location)),
                onSelected: (isSelected) {
                  final next = selected.toSet();
                  if (isSelected) {
                    next.add(location);
                  } else {
                    next.remove(location);
                  }
                  onChanged(next.toList(growable: false));
                },
                selectedColor: colors.selected,
                backgroundColor: colors.surfaceContainerHigh,
                checkmarkColor: colors.accent,
                labelStyle: typo.uiSmall.copyWith(
                  color: selectedSet.contains(location)
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.pill),
                  side: BorderSide(
                    color: selectedSet.contains(location)
                        ? colors.accent
                        : colors.borderSubtle,
                  ),
                ),
              ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(errorText!, style: typo.uiSmall.copyWith(color: colors.error)),
        ],
      ],
    );
  }

  String _locationLabel(
    BuildContext context,
    AiShortcutActionLocation location,
  ) {
    final key = switch (location) {
      AiShortcutActionLocation.novel_description =>
        LocaleKeys.agentShortcutLocationNovelDescription,
      AiShortcutActionLocation.chapter =>
        LocaleKeys.agentShortcutLocationChapter,
      AiShortcutActionLocation.outline =>
        LocaleKeys.agentShortcutLocationOutline,
      AiShortcutActionLocation.outline_beat =>
        LocaleKeys.agentShortcutLocationOutlineBeat,
      AiShortcutActionLocation.character =>
        LocaleKeys.agentShortcutLocationCharacter,
      AiShortcutActionLocation.worldbuilding =>
        LocaleKeys.agentShortcutLocationWorldbuilding,
      AiShortcutActionLocation.material =>
        LocaleKeys.agentShortcutLocationMaterial,
      AiShortcutActionLocation.skill_entry =>
        LocaleKeys.agentShortcutLocationSkillEntry,
      AiShortcutActionLocation.item => LocaleKeys.agentShortcutLocationItem,
      AiShortcutActionLocation.faction =>
        LocaleKeys.agentShortcutLocationFaction,
      AiShortcutActionLocation.creature =>
        LocaleKeys.agentShortcutLocationCreature,
      AiShortcutActionLocation.foreshadowing =>
        LocaleKeys.agentShortcutLocationForeshadowing,
    };
    return context.t(key);
  }
}
