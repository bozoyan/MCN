// 职责: 移动端流程智能体提示词编辑页，只编辑自定义提示词开关与提示词正文。
// 关联文件:
//   lib/mobile/pages/agent_model_settings_page.dart
//   lib/mobile/widgets/agent_edit_scaffold.dart
//   lib/shared/models/subagent.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/components/reveric_text_field.dart
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

import '../../shared/components/reveric_switch.dart';
import '../../shared/components/reveric_text_field.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/models/subagent.dart';
import '../../shared/providers/subagent_providers.dart';
import '../../shared/services/ai/builtin_agent_tools.dart';
import '../../shared/theme/theme.dart';
import '../../shared/utils/text_input_composing.dart';
import '../../third/form/flutter_hook_form.dart';
import '../widgets/agent_edit_scaffold.dart';

final _log = AppLogger.forModule('MobileSubAgentPromptEdit');

enum _PromptField implements FieldSchema {
  prompt,
  useCustomPrompt;

  @override
  List<Validator<dynamic>>? get validators => null;
}

/// 只允许修改子智能体提示词配置的移动端编辑页。
class MobileSubAgentPromptEditPage extends HookConsumerWidget {
  const MobileSubAgentPromptEditPage({super.key, required this.agent});

  final SubAgent agent;

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
    final saving = useState(false);
    final useCustom = isBuiltin
        ? form.getValue<bool>(_PromptField.useCustomPrompt) ?? false
        : true;
    final promptEditable = !isBuiltin || useCustom;

    Future<void> save() async {
      syncFormFieldsFromControllersBeforeValidate(
        form: form,
        fields: {_PromptField.prompt: promptController},
      );
      if (!form.validate()) {
        return;
      }
      final customPrompt = isBuiltin
          ? form.getValue<bool>(_PromptField.useCustomPrompt) ?? false
          : true;
      final prompt = customPrompt ? promptController.text.trim() : '';

      saving.value = true;
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
        if (context.mounted) {
          Navigator.of(context).pop();
        }
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
      } finally {
        if (context.mounted) {
          saving.value = false;
        }
      }
    }

    return MobileAgentEditScaffold(
      title: context.t(LocaleKeys.agentStudioEditPrompt),
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
                icon: RevericIcons.edit_note_outlined,
                emoji: agent.avatarEmoji,
                avatarPath: agent.avatarPath,
                avatarSlug: agent.slug,
                title: agent.name,
                subtitle: context.t(LocaleKeys.agentStudioEditPrompt),
              ),
              if (isBuiltin) ...[
                const SizedBox(height: RevericSpacing.x2l),
                Container(
                  padding: const EdgeInsets.all(RevericSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(RevericRadius.large),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t(LocaleKeys.subagentUseCustomPrompt),
                          style: typo.uiMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      HookedFormField<_PromptField, bool>(
                        fieldHook: _PromptField.useCustomPrompt,
                        notifyOnChange: true,
                        builder: (value, onChanged, error) => RevericSwitch(
                          value: value ?? false,
                          onChanged: (next) => onChanged?.call(next),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: RevericSpacing.x2l),
              AgentEditField(
                label: context.t(LocaleKeys.subagentPrompt),
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
                  builder: (value, onChanged, error) => RevericTextField(
                    fieldKey: const ValueKey(
                      'mobile_subagent_prompt_edit_field',
                    ),
                    controller: promptController,
                    multiline: true,
                    minLines: 12,
                    maxLines: null,
                    readOnly: !promptEditable,
                    enabled: promptEditable,
                    keyboardType: TextInputType.multiline,
                    hintText: context.t(LocaleKeys.subagentPromptHint),
                    errorText: error,
                    onChanged: (value) => onChanged?.call(value),
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
