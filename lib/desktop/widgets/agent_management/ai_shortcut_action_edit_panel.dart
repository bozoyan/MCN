// 职责: AI 快捷方式编辑面板 — 编辑全局快捷方式名称、指令、适用位置与执行选项。
// 关联文件:
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/components/reveric_switch.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/ai_shortcut_action.dart';
import '../../../shared/providers/ai_shortcut_action_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/text_input_composing.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../../third/form/flutter_hook_form.dart';
import '../desktop_window_frame.dart';
import '../../../shared/widgets/confirm_dialog.dart';

final _log = AppLogger.forModule('AIShortcut');

enum AiShortcutActionEditField<T> implements FieldSchema {
  name<String>(validators: [RequiredValidator<String>()]),
  prompt<String>(validators: [RequiredValidator<String>()]),
  locations<List<AiShortcutActionLocation>>(),
  enabled<bool>(),
  autoSend<bool>();

  const AiShortcutActionEditField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class AiShortcutActionEditPanel extends HookConsumerWidget {
  const AiShortcutActionEditPanel({
    super.key,
    required this.action,
    required this.onSaved,
    this.onCancel,
    this.onBack,
    this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    this.onHasChangesChanged,
    this.onRegisterSave,
  });

  final AiShortcutActionDefinition action;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final VoidCallback? onBack;
  final GlobalKey? headerGestureExclusionKey;
  final double headerTrailingInset;
  final ValueChanged<bool>? onHasChangesChanged;

  /// 向父级注册「保存当前编辑」的函数（返回是否保存成功），用于未保存变更
  /// 拦截 dialog 的「保存」按钮。组件卸载时回传 null 注销。
  final ValueChanged<Future<bool> Function()?>? onRegisterSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final form = useForm<AiShortcutActionEditField>(
      initialValues: {
        AiShortcutActionEditField.name: action.name,
        AiShortcutActionEditField.prompt: action.prompt,
        AiShortcutActionEditField.locations: action.locations,
        AiShortcutActionEditField.enabled: action.enabled,
        AiShortcutActionEditField.autoSend: action.autoSend,
      },
      keys: [action.id, action.updatedAt],
    );

    final nameController = useTextEditingController(text: action.name);
    final promptController = useTextEditingController(text: action.prompt);
    final promptFocusNode = useFocusNode();
    final isSaving = useState(false);
    final hasEdits = useState(false);
    final syncingControllersRef = useRef(false);

    // 注册「保存当前编辑」给父级（未保存变更拦截 dialog 用）。saveRef 每次
    // build 更新为最新的 save 闭包，注册的包装函数始终调用最新闭包。
    // 只在挂载时注册一次、卸载时注销：父级每次 build 都会重建 onRegisterSave
    // 闭包，若把它放进 keys 会触发「注销→重注册」抖动，且 hooks 会在新 setup
    // 之后才跑旧 cleanup，最终停在注销（null）上，导致父级拿不到保存函数。
    final onRegisterSaveRef = useRef(onRegisterSave);
    onRegisterSaveRef.value = onRegisterSave;
    final saveRef = useRef<Future<bool> Function()?>(null);
    useEffect(() {
      onRegisterSaveRef.value?.call(
        () async => await saveRef.value?.call() ?? false,
      );
      return () => onRegisterSaveRef.value?.call(null);
    }, const []);

    useEffect(
      () {
        syncingControllersRef.value = true;
        nameController.text = action.name;
        promptController.text = action.prompt;
        syncingControllersRef.value = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          hasEdits.value = false;
          onHasChangesChanged?.call(false);
        });
        return null;
      },
      [action.id, action.name, action.prompt, nameController, promptController],
    );

    bool computeHasEdits() {
      final locations =
          form.getValue<List<AiShortcutActionLocation>>(
            AiShortcutActionEditField.locations,
          ) ??
          action.locations;
      final enabled =
          form.getValue<bool>(AiShortcutActionEditField.enabled) ??
          action.enabled;
      final autoSend =
          form.getValue<bool>(AiShortcutActionEditField.autoSend) ??
          action.autoSend;
      if (nameController.text != action.name ||
          promptController.text != action.prompt ||
          enabled != action.enabled ||
          autoSend != action.autoSend) {
        return true;
      }
      if (locations.length != action.locations.length) {
        return true;
      }
      for (var i = 0; i < locations.length; i++) {
        if (locations[i] != action.locations[i]) {
          return true;
        }
      }
      return false;
    }

    void notifyDirtyIfNeeded({TextEditingController? composingController}) {
      notifyDirtyAfterExternalControllerEdit(
        focusToPreserve: promptFocusNode,
        suppress: syncingControllersRef.value,
        composingController: composingController,
        computeHasEdits: computeHasEdits,
        readHasEdits: () => hasEdits.value,
        writeHasEdits: (next) => hasEdits.value = next,
        onHasChangesChanged: onHasChangesChanged,
      );
    }

    useEffect(() {
      void onNameChanged() {
        notifyDirtyIfNeeded(composingController: nameController);
      }

      void onPromptChanged() {
        notifyDirtyIfNeeded(composingController: promptController);
      }

      nameController.addListener(onNameChanged);
      promptController.addListener(onPromptChanged);
      return () {
        nameController.removeListener(onNameChanged);
        promptController.removeListener(onPromptChanged);
      };
    }, [nameController, promptController, promptFocusNode]);

    final hasChanges = computeHasEdits();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHasChangesChanged?.call(hasChanges);
      });
      return null;
    }, [hasChanges, action.id]);

    // 仅负责持久化，返回是否保存成功；不做导航。导航由调用方（header 保存按钮
    // 成功后 onSaved，或父级未保存变更拦截 dialog）处理。
    Future<bool> save() async {
      syncFormFieldsFromControllersBeforeValidate(
        form: form,
        fields: {
          AiShortcutActionEditField.name: nameController,
          AiShortcutActionEditField.prompt: promptController,
        },
      );
      if (!form.validate()) {
        return false;
      }
      final locations =
          form.getValue<List<AiShortcutActionLocation>>(
            AiShortcutActionEditField.locations,
          ) ??
          const <AiShortcutActionLocation>[];
      if (locations.isEmpty) {
        form.setError(
          AiShortcutActionEditField.locations,
          context.t(LocaleKeys.agentShortcutLocationsRequired),
        );
        return false;
      }

      isSaving.value = true;
      try {
        final name =
            form.getValue<String>(AiShortcutActionEditField.name)?.trim() ?? '';
        final prompt = promptController.text.trim();
        final enabled =
            form.getValue<bool>(AiShortcutActionEditField.enabled) ?? true;
        final autoSend =
            form.getValue<bool>(AiShortcutActionEditField.autoSend) ?? false;

        if (action.id.startsWith('__new__')) {
          await ref
              .read(aiShortcutActionsProvider.notifier)
              .createAction(
                AiShortcutActionDraft(
                  name: name,
                  prompt: prompt,
                  locations: locations,
                  enabled: enabled,
                  autoSend: autoSend,
                ),
              );
        } else {
          await ref
              .read(aiShortcutActionsProvider.notifier)
              .updateAction(
                action.copyWith(
                  name: name,
                  prompt: prompt,
                  locations: locations,
                  enabled: enabled,
                  autoSend: autoSend,
                ),
              );
        }
        return true;
      } on AiShortcutActionNameConflictException catch (e) {
        if (!context.mounted) {
          return false;
        }
        form.setError(
          AiShortcutActionEditField.name,
          context.t(
            LocaleKeys.agentShortcutDuplicateName,
            namedArgs: {'name': e.name},
          ),
        );
        return false;
      } catch (error) {
        _log.error('save failed: $error', error: error);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
        return false;
      } finally {
        isSaving.value = false;
      }
    }

    saveRef.value = save;

    Future<void> saveFromHeader() async {
      if (await save()) {
        onSaved();
      }
    }

    return Container(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            action: action,
            hasChanges: hasChanges,
            isSaving: isSaving.value,
            enabled:
                form.getValue<bool>(AiShortcutActionEditField.enabled) ?? true,
            onToggleEnabled: (value) {
              form.updateValue(
                AiShortcutActionEditField.enabled,
                value,
                notify: true,
              );
              notifyDirtyIfNeeded();
            },
            onSave: saveFromHeader,
            onRestoreDefault: () => restoreDefault(context, ref),
            onCancel: onCancel,
            onBack: onBack,
            headerGestureExclusionKey: headerGestureExclusionKey,
            headerTrailingInset: headerTrailingInset,
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
              child: HookedForm(
                form: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderInfo(action: action),
                    const SizedBox(height: RevericSpacing.x3l),
                    _FieldLabel(LocaleKeys.agentShortcutName),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<AiShortcutActionEditField, String>(
                      fieldHook: AiShortcutActionEditField.name,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? context.t(LocaleKeys.agentShortcutNameRequired)
                          : null,
                      builder: (value, onChanged, error) {
                        return RevericTextField(
                          controller: nameController,
                          autofocus: action.id.startsWith('__new__'),
                          errorText: error,
                        );
                      },
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    _FieldLabel(LocaleKeys.agentShortcutApplicableLocations),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<
                      AiShortcutActionEditField,
                      List<AiShortcutActionLocation>
                    >(
                      fieldHook: AiShortcutActionEditField.locations,
                      builder: (value, onChanged, error) {
                        return _LocationSelector(
                          selected: value ?? const <AiShortcutActionLocation>[],
                          errorText: error,
                          onChanged: (next) {
                            onChanged?.call(next);
                            notifyDirtyIfNeeded();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    HookedFormField<AiShortcutActionEditField, bool>(
                      fieldHook: AiShortcutActionEditField.autoSend,
                      notifyOnChange: true,
                      builder: (value, onChanged, error) {
                        return _SwitchRow(
                          labelKey: LocaleKeys.agentShortcutAutoSend,
                          value: value ?? false,
                          onChanged: (next) {
                            onChanged?.call(next);
                            notifyDirtyIfNeeded();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    _FieldLabel(LocaleKeys.agentShortcutPrompt),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<AiShortcutActionEditField, String>(
                      fieldHook: AiShortcutActionEditField.prompt,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? context.t(LocaleKeys.agentShortcutPromptRequired)
                          : null,
                      builder: (value, onChanged, error) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 420,
                              child: RevericMarkdownEditor(
                                controller: promptController,
                                focusNode: promptFocusNode,
                                hintText: context.t(
                                  LocaleKeys.agentShortcutPromptHint,
                                ),
                              ),
                            ),
                            if (error != null) _FieldError(error),
                          ],
                        );
                      },
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

  Future<void> restoreDefault(BuildContext context, WidgetRef ref) async {
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
      variant: ConfirmDialogVariant.warning,
    );
    if (confirmed != true) {
      return;
    }
    await ref
        .read(aiShortcutActionsProvider.notifier)
        .restoreBuiltin(builtinId);
    if (context.mounted) {
      onSaved();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.action,
    required this.hasChanges,
    required this.isSaving,
    required this.enabled,
    required this.onToggleEnabled,
    required this.onSave,
    required this.onRestoreDefault,
    this.onCancel,
    this.onBack,
    this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
  });

  final AiShortcutActionDefinition action;
  final bool hasChanges;
  final bool isSaving;
  final bool enabled;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onSave;
  final VoidCallback onRestoreDefault;
  final VoidCallback? onCancel;
  final VoidCallback? onBack;
  final GlobalKey? headerGestureExclusionKey;
  final double headerTrailingInset;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      height: DesktopWindowFrame.titleBarHeight,
      padding: EdgeInsets.only(
        left: RevericSpacing.lg,
        right: RevericSpacing.lg + headerTrailingInset,
      ),
      color: colors.surfaceContainer,
      child: KeyedSubtree(
        key: headerGestureExclusionKey,
        child: Row(
          children: [
            if (onBack != null) ...[
              IconButton(
                onPressed: onBack,
                icon: const RevericIcon(RevericIcons.arrow_back, size: 16),
              ),
              const SizedBox(width: RevericSpacing.xs),
            ],
            Expanded(
              child: Text(
                action.name.isEmpty
                    ? context.t(LocaleKeys.commonUntitled)
                    : action.name,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              context.t(LocaleKeys.agentShortcutEnabled),
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: RevericSpacing.xs),
            RevericSwitch(value: enabled, onChanged: onToggleEnabled),
            const SizedBox(width: RevericSpacing.md),
            if (action.isBuiltin) ...[
              OutlinedButton.icon(
                onPressed: onRestoreDefault,
                icon: const RevericIcon(
                  RevericIcons.history_outlined,
                  size: 16,
                ),
                label: Text(context.t(LocaleKeys.agentShortcutRestoreDefault)),
              ),
              const SizedBox(width: RevericSpacing.sm),
            ],
            if (onCancel != null) ...[
              TextButton(
                onPressed: hasChanges ? onCancel : null,
                child: Text(context.t(LocaleKeys.commonCancel)),
              ),
              const SizedBox(width: RevericSpacing.sm),
            ],
            FilledButton(
              onPressed: isSaving || !hasChanges ? null : onSave,
              child: Text(
                isSaving
                    ? context.t(LocaleKeys.commonSaving)
                    : context.t(LocaleKeys.commonSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  const _HeaderInfo({required this.action});

  final AiShortcutActionDefinition action;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput, width: 2),
          ),
          child: RevericIcon(
            RevericIcons.rocket_launch_outlined,
            size: 28,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: RevericSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.name.isEmpty
                    ? context.t(LocaleKeys.commonUntitled)
                    : action.name,
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                action.isBuiltin
                    ? context.t(LocaleKeys.agentShortcutBuiltin)
                    : context.t(LocaleKeys.agentShortcutCustom),
                style: typo.bodySmall.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.localeKey);

  final String localeKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      context.t(localeKey),
      style: typo.uiSemibold.copyWith(color: colors.textSecondary),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: RevericSpacing.xs),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.warning_amber_rounded,
            size: 14,
            color: colors.warningText,
          ),
          const SizedBox(width: RevericSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: typo.uiSmall.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Text(
          context.t(labelKey),
          style: typo.ui.copyWith(color: colors.textSecondary),
        ),
        const Spacer(),
        RevericSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

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
        if (errorText != null) _FieldError(errorText!),
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
