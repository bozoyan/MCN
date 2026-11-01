// 职责: 桌面端流程智能体提示词编辑面板，只编辑自定义提示词开关与提示词正文。
// 关联文件:
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/edit_panel_breadcrumb.dart
//   lib/shared/models/subagent.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_studio.json
//   assets/translations/zh-CN/agent_studio.json
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_switch.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/subagent.dart';
import '../../../shared/providers/subagent_providers.dart';
import '../../../shared/services/ai/builtin_agent_tools.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/text_input_composing.dart';
import '../../../shared/widgets/agent_avatar.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../../../third/form/flutter_hook_form.dart';
import '../desktop_window_frame.dart';
import '../edit_panel_breadcrumb.dart';

final _log = AppLogger.forModule('SubAgentPromptEdit');

enum _PromptField implements FieldSchema {
  prompt,
  useCustomPrompt;

  @override
  List<Validator<dynamic>>? get validators => null;
}

/// 只允许修改子智能体提示词配置的桌面端编辑面板。
class SubAgentPromptEditPanel extends HookConsumerWidget {
  const SubAgentPromptEditPanel({
    super.key,
    required this.agent,
    required this.onBack,
    required this.onSaved,
    this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    this.onHasChangesChanged,
    this.onRegisterSave,
  });

  final SubAgent agent;
  final VoidCallback onBack;
  final VoidCallback onSaved;
  final GlobalKey? headerGestureExclusionKey;
  final double headerTrailingInset;
  final ValueChanged<bool>? onHasChangesChanged;
  final ValueChanged<Future<bool> Function()?>? onRegisterSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isBuiltin = builtinSubAgentSlugs.contains(agent.slug);
    final form = useForm<_PromptField>(
      initialValues: {
        _PromptField.prompt: agent.prompt,
        _PromptField.useCustomPrompt: isBuiltin ? agent.useCustomPrompt : true,
      },
      keys: [agent.id, agent.updatedAt],
    );
    final promptController = useTextEditingController(text: agent.prompt);
    final promptFocusNode = useFocusNode();
    final isSaving = useState(false);
    final hasEdits = useState(false);
    final useCustom = isBuiltin
        ? form.getValue<bool>(_PromptField.useCustomPrompt) ?? false
        : true;
    final promptEditable = !isBuiltin || useCustom;

    bool computeHasEdits() {
      final customPrompt = isBuiltin
          ? form.getValue<bool>(_PromptField.useCustomPrompt) ?? false
          : true;
      final currentPrompt = customPrompt ? promptController.text : '';
      final baselinePrompt = agent.useCustomPrompt || !isBuiltin
          ? agent.prompt
          : '';
      return customPrompt != (isBuiltin ? agent.useCustomPrompt : true) ||
          currentPrompt != baselinePrompt;
    }

    void notifyDirtyIfNeeded({TextEditingController? composingController}) {
      notifyDirtyAfterExternalControllerEdit(
        focusToPreserve: promptFocusNode,
        suppress: false,
        composingController: composingController,
        computeHasEdits: computeHasEdits,
        readHasEdits: () => hasEdits.value,
        writeHasEdits: (next) => hasEdits.value = next,
        onHasChangesChanged: onHasChangesChanged,
      );
    }

    useOnListenableChange(
      promptController,
      () => notifyDirtyIfNeeded(composingController: promptController),
    );

    final saveRef = useRef<Future<bool> Function()?>(null);
    final onRegisterSaveRef = useRef(onRegisterSave);
    onRegisterSaveRef.value = onRegisterSave;
    useEffect(() {
      onRegisterSaveRef.value?.call(
        () async => await saveRef.value?.call() ?? false,
      );
      return () => onRegisterSaveRef.value?.call(null);
    }, const []);

    Future<bool> save() async {
      syncFormFieldsFromControllersBeforeValidate(
        form: form,
        fields: {_PromptField.prompt: promptController},
      );
      if (!form.validate()) {
        return false;
      }
      final customPrompt = isBuiltin
          ? form.getValue<bool>(_PromptField.useCustomPrompt) ?? false
          : true;
      final prompt = customPrompt ? promptController.text.trim() : '';

      isSaving.value = true;
      try {
        await ref
            .read(globalSubAgentsProvider.notifier)
            .updateSubAgent(
              agent.copyWith(prompt: prompt, useCustomPrompt: customPrompt),
            );
        if (!customPrompt) {
          ref.invalidate(globalSubAgentsProvider);
          await ref.read(globalSubAgentsProvider.future);
        }
        hasEdits.value = false;
        onHasChangesChanged?.call(false);
        return true;
      } catch (error, stackTrace) {
        _log.error(
          'save prompt failed id=${agent.id}',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
        return false;
      } finally {
        if (context.mounted) {
          isSaving.value = false;
        }
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
          Container(
            height: DesktopWindowFrame.titleBarHeight,
            padding: EdgeInsets.only(
              right: RevericSpacing.lg + headerTrailingInset,
            ),
            color: colors.surfaceContainer,
            child: KeyedSubtree(
              key: headerGestureExclusionKey,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const RevericIcon(
                      RevericIcons.arrow_back,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  Expanded(
                    child: EditPanelBreadcrumb(
                      rootLabel: context.t(LocaleKeys.agentStudioModelSettings),
                      title: context.t(LocaleKeys.agentStudioEditPrompt),
                    ),
                  ),
                  FilledButton(
                    onPressed: isSaving.value || !hasEdits.value
                        ? null
                        : saveFromHeader,
                    child: Text(
                      isSaving.value
                          ? context.t(LocaleKeys.commonSaving)
                          : context.t(LocaleKeys.commonSave),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x6l,
                RevericSpacing.x4l,
                RevericSpacing.x6l,
                RevericSpacing.x5l,
              ),
              child: HookedForm(
                form: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AgentAvatar(
                          avatarPath: agent.avatarPath,
                          slug: agent.slug,
                          avatarEmoji: agent.avatarEmoji,
                          size: RevericSizes.buttonHeight,
                        ),
                        const SizedBox(width: RevericSpacing.lg),
                        Expanded(
                          child: Text(
                            agent.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typo.uiSemibold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (isBuiltin) ...[
                          Text(
                            context.t(LocaleKeys.subagentUseCustomPrompt),
                            style: typo.uiSmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: RevericSpacing.xs),
                          HookedFormField<_PromptField, bool>(
                            fieldHook: _PromptField.useCustomPrompt,
                            notifyOnChange: true,
                            builder: (value, onChanged, error) =>
                                RevericSwitch(
                                  value: value ?? false,
                                  onChanged: (next) {
                                    onChanged?.call(next);
                                    notifyDirtyIfNeeded();
                                  },
                                ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.x3l),
                    Text(
                      context.t(LocaleKeys.subagentPrompt),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    Expanded(
                      child: HookedFormField<_PromptField, String>(
                        fieldHook: _PromptField.prompt,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (!promptEditable) {
                            return null;
                          }
                          return (value == null || value.trim().isEmpty)
                              ? context.t(LocaleKeys.subagentPromptRequired)
                              : null;
                        },
                        builder: (value, onChanged, error) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
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
                              Text(
                                error,
                                style: typo.uiSmall.copyWith(
                                  color: colors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
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
