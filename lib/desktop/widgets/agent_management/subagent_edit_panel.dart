// 职责: 专家编辑面板 — 提供身份、提示词、模型、推理强度、启用状态的编辑界面
// 关联文件:
//   lib/shared/models/subagent.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_switch.dart
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/shared/widgets/ai/reasoning_effort_bars.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/utils/text_input_composing.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/icons.md
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/services/ai/builtin_agent_tools.dart';
import '../../../shared/components/reveric_select.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/components/reveric_switch.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/subagent.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/providers/subagent_providers.dart';
import '../../../shared/services/ai/prompt_template.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/text_input_composing.dart';
import '../../../shared/utils/storage_paths.dart';
import '../../../shared/widgets/agent_avatar.dart';
import '../../../shared/widgets/ai/reasoning_effort_bars.dart';
import '../../../third/form/flutter_hook_form.dart';
import '../ai/model/model_selector.dart';
import '../desktop_window_frame.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';

final _log = AppLogger.forModule('SubAgent');

enum SubAgentEditFields implements FieldSchema {
  name(validators: [RequiredValidator<String>()], initialValue: ''),
  description(validators: [RequiredValidator<String>()], initialValue: ''),
  prompt(initialValue: ''),
  useCustomPrompt(initialValue: false),
  modelId(initialValue: null),
  reasoningEffort(initialValue: null),
  enabled(initialValue: true),
  mode(
    validators: [RequiredValidator<SubAgentMode>()],
    initialValue: SubAgentMode.chat,
  );

  const SubAgentEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

String _defaultPromptFromAsset(String slug) {
  if (!builtinSubAgentSlugs.contains(slug)) return '';
  if (!PromptTemplateService.isInitialized) return '';
  try {
    return PromptTemplateService.instance.rawAsset(
      'assets/prompts/agent/$slug',
    );
  } catch (_) {
    return '';
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

class SubAgentEditPanel extends HookConsumerWidget {
  const SubAgentEditPanel({
    super.key,
    required this.agent,
    this.novelId,
    this.headerLeadingInset = 0,
    this.headerTrailingInset = 0,
    this.headerGestureExclusionKey,
    this.onBack,
    required this.onSaved,
    this.onCancel,
    this.onHasChangesChanged,
    this.onRegisterSave,
    this.readOnly = false,
  });

  final SubAgent agent;
  final String? novelId;
  final double headerLeadingInset;
  final double headerTrailingInset;
  final GlobalKey? headerGestureExclusionKey;
  final VoidCallback? onBack;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final ValueChanged<bool>? onHasChangesChanged;

  /// 向父级注册「保存当前编辑」的函数（返回是否保存成功），用于未保存变更
  /// 拦截 dialog 的「保存」按钮。组件卸载时回传 null 注销。
  final ValueChanged<Future<bool> Function()?>? onRegisterSave;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final initialModelId = agent.providerId != null && agent.model != null
        ? '${agent.providerId}::${agent.model}'
        : null;
    final defaultPrompt = _defaultPromptFromAsset(agent.slug);
    final hasDefaultPrompt = defaultPrompt.isNotEmpty;

    // keys 中加入 updatedAt：home 在 save 成功后会把 selection 切到
    // provider 最新版本的 agent，updatedAt 变化会触发 useForm 重建，
    // 从而把 form.hasChanged 复位。
    final form = useForm<SubAgentEditFields>(
      initialValues: {
        SubAgentEditFields.name: agent.name,
        SubAgentEditFields.description: agent.description,
        SubAgentEditFields.prompt: agent.prompt,
        SubAgentEditFields.useCustomPrompt: hasDefaultPrompt
            ? agent.useCustomPrompt
            : true,
        SubAgentEditFields.modelId: initialModelId,
        SubAgentEditFields.reasoningEffort: agent.reasoningEffort,
        SubAgentEditFields.enabled: agent.enabled,
        SubAgentEditFields.mode: SubAgentMode.fromString(agent.mode),
      },
      keys: [agent.id, agent.updatedAt],
    );

    final nameController = useTextEditingController(text: agent.name);
    final descriptionController = useTextEditingController(
      text: agent.description,
    );
    final promptController = useTextEditingController(
      text: agent.useCustomPrompt || !hasDefaultPrompt
          ? agent.prompt
          : defaultPrompt,
    );
    final promptFocusNode = useFocusNode();
    final isSaving = useState(false);
    final hasEdits = useState(false);
    final syncingControllersRef = useRef(false);
    final avatarPath = useState<String>(agent.avatarPath ?? '');

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
    final useCustom =
        form.getValue<bool>(SubAgentEditFields.useCustomPrompt) ?? false;
    final promptEditable = !readOnly && (!hasDefaultPrompt || useCustom);

    Future<void> pickAvatar() async {
      final result = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          ),
        ],
      );
      if (result != null) {
        final source = File(result.path);
        final appDir = await getApplicationSupportDirectory();
        final avatarDir = Directory(p.join(appDir.path, 'agent_avatars'));
        if (!await avatarDir.exists()) {
          await avatarDir.create(recursive: true);
        }
        final ext = p.extension(source.path);
        final dest = File(p.join(avatarDir.path, '${agent.id}$ext'));
        await source.copy(dest.path);
        avatarPath.value = dest.path;
      }
    }

    Future<void> clearAvatar() async {
      // 存储值可能是相对/旧绝对路径，先 resolve 再删，避免删不到。
      final resolved = RevericPaths.resolveStored(avatarPath.value);
      if (resolved != null) {
        await File(resolved).delete();
      }
      avatarPath.value = '';
    }

    useEffect(
      () {
        syncingControllersRef.value = true;
        nameController.text = agent.name;
        descriptionController.text = agent.description;
        if (agent.useCustomPrompt || !hasDefaultPrompt) {
          promptController.text = agent.prompt;
        } else {
          promptController.text = defaultPrompt;
        }
        form.updateValue(
          SubAgentEditFields.useCustomPrompt,
          hasDefaultPrompt ? agent.useCustomPrompt : true,
          notify: true,
        );
        syncingControllersRef.value = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          hasEdits.value = false;
          onHasChangesChanged?.call(false);
        });
        return null;
      },
      [
        agent.id,
        agent.updatedAt,
        agent.name,
        agent.description,
        agent.prompt,
        agent.useCustomPrompt,
        defaultPrompt,
        hasDefaultPrompt,
        form,
        nameController,
        descriptionController,
        promptController,
      ],
    );

    useEffect(
      () {
        // 无内置默认提示词时无需切换 prompt 文本；切勿先把
        // syncingControllersRef 置 true 再 early-return，否则 dirty
        // 通知会被永久 suppress，保存按钮一直禁用。
        if (!hasDefaultPrompt) {
          return null;
        }
        syncingControllersRef.value = true;
        if (useCustom) {
          final saved = agent.prompt.trim();
          promptController.text = saved.isNotEmpty ? saved : defaultPrompt;
        } else {
          promptController.text = defaultPrompt;
        }
        syncingControllersRef.value = false;
        return null;
      },
      [
        useCustom,
        hasDefaultPrompt,
        defaultPrompt,
        agent.prompt,
        promptController,
      ],
    );

    bool computeHasEdits() {
      final enabled =
          form.getValue<bool>(SubAgentEditFields.enabled) ?? agent.enabled;
      final useCustomPrompt =
          form.getValue<bool>(SubAgentEditFields.useCustomPrompt) ??
          (hasDefaultPrompt ? agent.useCustomPrompt : true);
      final modelId = form.getValue<String?>(SubAgentEditFields.modelId);
      final reasoningEffort = form.getValue<String?>(
        SubAgentEditFields.reasoningEffort,
      );
      final mode =
          form.getValue<SubAgentMode>(SubAgentEditFields.mode) ??
          SubAgentMode.fromString(agent.mode);
      final baselinePrompt = agent.useCustomPrompt || !hasDefaultPrompt
          ? agent.prompt
          : defaultPrompt;
      return nameController.text != agent.name ||
          descriptionController.text != agent.description ||
          promptController.text != baselinePrompt ||
          useCustomPrompt !=
              (hasDefaultPrompt ? agent.useCustomPrompt : true) ||
          enabled != agent.enabled ||
          avatarPath.value != (agent.avatarPath ?? '') ||
          modelId != initialModelId ||
          reasoningEffort != agent.reasoningEffort ||
          mode != SubAgentMode.fromString(agent.mode);
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

    useEffect(
      () {
        void onNameChanged() {
          notifyDirtyIfNeeded(composingController: nameController);
        }

        void onDescriptionChanged() {
          notifyDirtyIfNeeded(composingController: descriptionController);
        }

        void onPromptChanged() {
          notifyDirtyIfNeeded(composingController: promptController);
        }

        nameController.addListener(onNameChanged);
        descriptionController.addListener(onDescriptionChanged);
        promptController.addListener(onPromptChanged);
        return () {
          nameController.removeListener(onNameChanged);
          descriptionController.removeListener(onDescriptionChanged);
          promptController.removeListener(onPromptChanged);
        };
      },
      [
        nameController,
        descriptionController,
        promptController,
        promptFocusNode,
      ],
    );

    final settingsAsync = ref.watch(appSettingsProvider);
    final aiSettings = settingsAsync.asData?.value.aiSettings;
    final availableModels = aiSettings?.availableModelOptions ?? [];

    const disabledModelIds = <String>{};

    // 仅负责持久化，返回是否保存成功；不做导航。
    Future<bool> save() async {
      syncFormFieldsFromControllersBeforeValidate(
        form: form,
        fields: {
          SubAgentEditFields.name: nameController,
          SubAgentEditFields.description: descriptionController,
          SubAgentEditFields.prompt: promptController,
        },
      );
      if (!form.validate()) return false;

      final name = nameController.text.trim();
      final slug = agent.id.startsWith('__new__')
          ? _slugForNewExpert(name, agent.id)
          : agent.slug;
      final description =
          form.getValue<String>(SubAgentEditFields.description) ?? '';
      final prompt = promptController.text.trim();
      final useCustomPrompt = hasDefaultPrompt
          ? form.getValue<bool>(SubAgentEditFields.useCustomPrompt) ?? false
          : true;
      final promptToSave = useCustomPrompt ? prompt : '';
      final enabledValue =
          form.getValue<bool>(SubAgentEditFields.enabled) ?? true;
      final modelId = form.getValue<String?>(SubAgentEditFields.modelId);
      final reasoningEffort = form.getValue<String?>(
        SubAgentEditFields.reasoningEffort,
      );
      final mode =
          (form.getValue<SubAgentMode>(SubAgentEditFields.mode) ??
                  SubAgentMode.chat)
              .value;

      isSaving.value = true;
      try {
        String? providerId;
        String? model;
        if (modelId != null) {
          final parts = modelId.split('::');
          if (parts.length == 2) {
            providerId = parts[0];
            model = parts[1];
          }
        }
        final selectedOption = modelId == null
            ? null
            : availableModels.where((o) => o.id == modelId).firstOrNull;
        final effortToSave = reasoningEffortForOption(
          selectedOption,
          reasoningEffort,
        );

        // 头像存相对路径（相对 Application Support 根），根外/兜底保留原值。
        final avatarToStore = avatarPath.value.isNotEmpty
            ? (RevericPaths.toRelative(avatarPath.value) ?? avatarPath.value)
            : null;

        if (agent.id.startsWith('__new__')) {
          final draft = SubAgentDraft(
            slug: slug,
            name: name,
            description: description,
            prompt: promptToSave,
            mode: mode,
            scope: SubAgentScope.global,
            useCustomPrompt: useCustomPrompt,
            providerId: providerId,
            model: model,
            reasoningEffort: effortToSave,
            avatarPath: avatarToStore,
          );
          await ref
              .read(globalSubAgentsProvider.notifier)
              .createSubAgent(draft);
        } else {
          final updated = agent.copyWith(
            slug: slug,
            name: name,
            description: description,
            prompt: promptToSave,
            mode: mode,
            enabled: enabledValue,
            useCustomPrompt: useCustomPrompt,
            providerId: providerId,
            model: model,
            reasoningEffort: effortToSave,
            avatarPath: avatarToStore,
          );

          await ref
              .read(globalSubAgentsProvider.notifier)
              .updateSubAgent(updated);
        }

        return true;
      } on SubAgentNameConflictException {
        if (!context.mounted) return false;
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
        return false;
      } catch (error) {
        _log.error('Save failed', error: error);
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

    final hasChanges = computeHasEdits();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHasChangesChanged?.call(hasChanges);
      });
      return null;
    }, [hasChanges, agent.id]);

    return Container(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            hasChanges: hasChanges,
            isSaving: isSaving.value,
            enabled: form.getValue<bool>(SubAgentEditFields.enabled) ?? true,
            onBack: onBack,
            onToggleEnabled: (v) {
              form.updateValue(SubAgentEditFields.enabled, v, notify: true);
              notifyDirtyIfNeeded();
            },
            onSave: saveFromHeader,
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
                    _buildHeaderInfo(
                      context,
                      avatarPath: avatarPath.value,
                      slug: agent.slug,
                      avatarEmoji: agent.avatarEmoji,
                      onPick: pickAvatar,
                      onClear: clearAvatar,
                    ),
                    const SizedBox(height: RevericSpacing.x4l),
                    _buildFieldLabel(context, LocaleKeys.subagentName),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<SubAgentEditFields, String>(
                      fieldHook: SubAgentEditFields.name,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? context.t(LocaleKeys.subagentNameRequired)
                          : null,
                      builder: (value, onChanged, error) {
                        return _buildTextField(
                          context,
                          controller: nameController,
                          editable: !readOnly,
                          errorText: error,
                        );
                      },
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    _buildFieldLabel(context, LocaleKeys.subagentDescription),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<SubAgentEditFields, String>(
                      fieldHook: SubAgentEditFields.description,
                      builder: (value, onChanged, error) {
                        return _buildTextField(
                          context,
                          controller: descriptionController,
                          editable: !readOnly,
                          errorText: error,
                          maxLines: 3,
                          keyboardType: TextInputType.multiline,
                        );
                      },
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    // Behavior row: mode | model (50/50)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel(
                                context,
                                LocaleKeys.subagentMode,
                              ),
                              const SizedBox(height: RevericSpacing.sm),
                              HookedFormField<SubAgentEditFields, SubAgentMode>(
                                fieldHook: SubAgentEditFields.mode,
                                notifyOnChange: true,
                                builder: (value, onChanged, error) {
                                  return _buildModeSelector(
                                    context,
                                    selectedMode: value ?? SubAgentMode.chat,
                                    onSelect: (mode) => onChanged?.call(mode),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.x2l),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel(
                                context,
                                LocaleKeys.subagentModel,
                              ),
                              const SizedBox(height: RevericSpacing.sm),
                              HookedFormField<SubAgentEditFields, String?>(
                                fieldHook: SubAgentEditFields.modelId,
                                notifyOnChange: true,
                                builder: (value, onChanged, error) {
                                  final selectedOption = value == null
                                      ? null
                                      : availableModels
                                            .where((o) => o.id == value)
                                            .firstOrNull;
                                  final selectedEffort =
                                      reasoningEffortForOption(
                                        selectedOption,
                                        form.getValue<String?>(
                                          SubAgentEditFields.reasoningEffort,
                                        ),
                                      );
                                  return ModelSelector.field(
                                    key: const ValueKey(
                                      'expert_edit_model_selector',
                                    ),
                                    availableModels: availableModels,
                                    selectedId: value,
                                    selectedEffort: selectedEffort,
                                    disabledModelIds: disabledModelIds,

                                    onChanged: (id) {
                                      onChanged?.call(id);
                                      final option = id == null
                                          ? null
                                          : availableModels
                                                .where((o) => o.id == id)
                                                .firstOrNull;
                                      form.updateValue(
                                        SubAgentEditFields.reasoningEffort,
                                        defaultEffortFor(option),
                                        notify: true,
                                      );
                                      notifyDirtyIfNeeded();
                                    },
                                    onSelectWithEffort: (option, effort) {
                                      onChanged?.call(option.id);
                                      form.updateValue(
                                        SubAgentEditFields.reasoningEffort,
                                        effort,
                                        notify: true,
                                      );
                                      notifyDirtyIfNeeded();
                                    },
                                    placeholder: context.t(
                                      LocaleKeys.subagentModelNotSelected,
                                    ),
                                    emptyMessage: context.t(
                                      LocaleKeys.subagentNoModelsAvailable,
                                    ),
                                    enabled: !readOnly,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _buildFieldLabel(
                            context,
                            LocaleKeys.subagentPrompt,
                          ),
                        ),
                        if (hasDefaultPrompt)
                          HookedFormField<SubAgentEditFields, bool>(
                            fieldHook: SubAgentEditFields.useCustomPrompt,
                            notifyOnChange: true,
                            builder: (value, onChanged, error) {
                              final custom = value ?? false;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.t(
                                      LocaleKeys.subagentUseCustomPrompt,
                                    ),
                                    style: typo.uiSmall.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: RevericSpacing.xs),
                                  RevericSwitch(
                                    value: custom,
                                    onChanged: readOnly
                                        ? null
                                        : (v) => onChanged?.call(v),
                                  ),
                                ],
                              );
                            },
                          ),
                        if (hasDefaultPrompt && useCustom && !readOnly) ...[
                          const SizedBox(width: RevericSpacing.sm),
                          TextButton.icon(
                            onPressed: () {
                              promptController.text = defaultPrompt;
                            },
                            icon: const RevericIcon(
                              RevericIcons.undo,
                              size: 16,
                            ),
                            label: Text(context.t(LocaleKeys.commonReset)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<SubAgentEditFields, String>(
                      fieldHook: SubAgentEditFields.prompt,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (hasDefaultPrompt && !useCustom) {
                          return null;
                        }
                        return (value == null || value.trim().isEmpty)
                            ? context.t(LocaleKeys.subagentPromptRequired)
                            : null;
                      },
                      builder: (value, onChanged, error) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 400,
                              child: RevericMarkdownEditor(
                                controller: promptController,
                                focusNode: promptFocusNode,
                                disabled: !promptEditable,
                                hintText: context.t(
                                  LocaleKeys.subagentPromptHint,
                                ),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: RevericSpacing.xs),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: RevericSpacing.xs,
                                ),
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
                                        error,
                                        style: typo.uiSmall.copyWith(
                                          color: colors.warningText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  Widget _buildHeader(
    BuildContext context, {
    required bool hasChanges,
    required bool isSaving,
    required bool enabled,
    required VoidCallback? onBack,
    required ValueChanged<bool> onToggleEnabled,
    required VoidCallback onSave,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      height: DesktopWindowFrame.titleBarHeight,
      padding: EdgeInsets.only(
        left: headerLeadingInset,
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
              child: Padding(
                padding: const EdgeInsets.only(left: RevericSpacing.lg),
                child: Text(
                  agent.name.isEmpty
                      ? context.t(LocaleKeys.commonUntitled)
                      : agent.name,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (readOnly)
              Container(
                margin: const EdgeInsets.only(right: RevericSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.md,
                  vertical: RevericSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.selected,
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RevericIcon(
                      RevericIcons.lock_outline,
                      size: 12,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: RevericSpacing.xs),
                    Text(
                      context.t(LocaleKeys.commonReadOnly),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            if (!readOnly) ...[
              // Enabled switch — placed in header so user can toggle without
              // scrolling, and to reclaim the awkward 3-column body row.
              Text(
                context.t(LocaleKeys.subagentEnabled),
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: RevericSpacing.xs),
              RevericSwitch(value: enabled, onChanged: onToggleEnabled),
              const SizedBox(width: RevericSpacing.md),
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
            if (hasChanges && readOnly)
              Padding(
                padding: const EdgeInsets.only(right: RevericSpacing.sm),
                child: Text(
                  context.t(LocaleKeys.commonUnsaved),
                  style: typo.uiTiny.copyWith(
                    color: colors.warningText,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderInfo(
    BuildContext context, {
    required String avatarPath,
    required String? slug,
    required String? avatarEmoji,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = agent.name.isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : agent.name;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: readOnly ? null : onPick,
          child: AgentAvatar(
            avatarPath: avatarPath.isNotEmpty ? avatarPath : null,
            slug: slug,
            avatarEmoji: avatarEmoji,
            size: 64,
            backgroundColor: colors.surfaceDim,
            border: Border.all(color: colors.borderInput, width: 2),
          ),
        ),
        const SizedBox(width: RevericSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.commonEdit),
                style: typo.bodySmall.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        if (!readOnly) ...[
          const SizedBox(width: RevericSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onPick,
                icon: const RevericIcon(RevericIcons.image, size: 16),
                label: Text(context.t(LocaleKeys.commonSelectImage)),
              ),
              if (avatarPath.isNotEmpty)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const RevericIcon(RevericIcons.close, size: 16),
                  label: Text(
                    context.t(LocaleKeys.commonRemove),
                    style: typo.uiSmall.copyWith(color: colors.warningText),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required bool editable,
    ValueChanged<String>? onChanged,
    String? errorText,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    final colors = RevericTheme.colorsOf(context);

    return RevericTextField(
      controller: controller,
      enabled: editable,
      readOnly: !editable,
      multiline: maxLines > 1,
      minLines: maxLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      fillColor: editable
          ? colors.surfaceContainerHigh
          : colors.surfaceContainerHigh.withValues(alpha: 0.5),
      suffixIcon: suffixIcon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: RevericSpacing.lg),
              child: suffixIcon,
            ),
      // 收紧 suffix 约束，避免小锁图标占据 Material 默认 48×48 的大块留白。
      suffixIconConstraints: suffixIcon == null
          ? null
          : const BoxConstraints(minWidth: 0, minHeight: 0),
      onChanged: editable ? onChanged : null,
    );
  }

  Widget _buildFieldLabel(BuildContext context, String localeKey) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Text(
      context.t(localeKey),
      style: typo.uiSemibold.copyWith(color: colors.textSecondary),
    );
  }

  Widget _buildModeSelector(
    BuildContext context, {
    required SubAgentMode selectedMode,
    required ValueChanged<SubAgentMode> onSelect,
  }) {
    return RevericSelect<SubAgentMode>(
      value: selectedMode,
      items: [
        RevericSelectItem(
          value: SubAgentMode.chat,
          label: context.t(LocaleKeys.subagentModeChat),
          icon: RevericIcons.chat_outlined,
        ),
        RevericSelectItem(
          value: SubAgentMode.council,
          label: context.t(LocaleKeys.subagentModeCouncil),
          icon: RevericIcons.groups_outlined,
        ),
      ],
      onChanged: onSelect,
      enabled: !readOnly,
      leadingIcon: selectedMode == SubAgentMode.chat
          ? RevericIcons.chat_outlined
          : RevericIcons.groups_outlined,
    );
  }
}
