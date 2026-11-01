// 职责: 移动端「提示词」管理 — 列出主笔智能体（primary agent）并编辑其名称/描述/系统提示词（内置可切换自定义）。
// 关联文件:
//   lib/shared/providers/agent_profile_providers.dart
//   lib/shared/models/agent_profile.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/mobile/widgets/agent_edit_scaffold.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
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
import '../../shared/models/agent_profile.dart';
import '../../shared/providers/agent_profile_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/agent_avatar.dart';
import '../../third/form/flutter_hook_form.dart';
import '../widgets/agent_edit_scaffold.dart';
import '../widgets/section_scaffold.dart';

final _log = AppLogger.forModule('MobileAgentPrompt');

/// 「提示词」管理列表页（主笔智能体，不支持新增）。
class MobileAgentPromptManagePage extends ConsumerWidget {
  const MobileAgentPromptManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final profilesAsync = ref.watch(globalAgentProfilesProvider);
    final profiles = profilesAsync.asData?.value ?? const <AgentProfile>[];

    void openEdit(AgentProfile profile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PromptEditPage(profile: profile),
        ),
      );
    }

    return MobileManageScaffold(
      title: context.t(LocaleKeys.mobileAssistantPromptsTitle),
      child: profilesAsync.isLoading && profiles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : MobileSectionListScaffold(
              showCreateBar: false,
              createLabel: context.t(LocaleKeys.commonEdit),
              onCreate: () {},
              emptyIcon: RevericIcons.edit_note_outlined,
              emptySectionLabel: context.t(
                LocaleKeys.mobileAssistantPromptsTitle,
              ),
              emptyHint: context.t(LocaleKeys.subagentEmpty),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];
                return MobileSectionCard(
                  onTap: () => openEdit(profile),
                  child: Row(
                    children: [
                      AgentAvatar(
                        avatarPath: profile.avatarPath,
                        slug: profile.slug,
                        avatarEmoji: profile.avatarEmoji,
                        size: 42,
                        backgroundColor: colors.accent.withValues(alpha: 0.13),
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RevericTheme.typographyOf(
                                context,
                              ).uiSemibold.copyWith(color: colors.textPrimary),
                            ),
                            const SizedBox(height: RevericSpacing.xs),
                            MobileSectionPreviewText(
                              preview: profile.description,
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
            ),
    );
  }
}

enum _Field implements FieldSchema {
  name(validators: [RequiredValidator<String>()]),
  description(),
  prompt(),
  useCustomPrompt();

  const _Field({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class _PromptEditPage extends HookConsumerWidget {
  const _PromptEditPage({required this.profile});

  final AgentProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isBuiltin = profile.isBuiltin;

    final form = useForm<_Field>(
      initialValues: {
        _Field.name: profile.name,
        _Field.description: profile.description,
        _Field.prompt: profile.systemPrompt,
        _Field.useCustomPrompt: isBuiltin ? profile.useCustomPrompt : true,
      },
      keys: [profile.id],
    );

    final nameCtrl = useTextEditingController(text: profile.name);
    final descCtrl = useTextEditingController(text: profile.description);
    final promptCtrl = useTextEditingController(text: profile.systemPrompt);
    final saving = useState(false);

    final useCustom = form.getValue<bool>(_Field.useCustomPrompt) ?? true;
    final promptEditable = !isBuiltin || useCustom;

    Future<void> save() async {
      if (!form.validate()) {
        return;
      }
      saving.value = true;
      try {
        final customPrompt = isBuiltin
            ? (form.getValue<bool>(_Field.useCustomPrompt) ?? false)
            : true;
        final updated = profile.copyWith(
          name: nameCtrl.text.trim(),
          description: descCtrl.text.trim(),
          systemPrompt: customPrompt ? promptCtrl.text.trim() : '',
          useCustomPrompt: customPrompt,
        );
        await ref
            .read(globalAgentProfilesProvider.notifier)
            .updateAgentProfile(updated);
        if (context.mounted) {
          Navigator.of(context).pop();
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
      title: profile.name,
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
                emoji: profile.avatarEmoji,
                avatarPath: profile.avatarPath,
                avatarSlug: profile.slug,
                title: profile.name,
                subtitle: context.t(LocaleKeys.mobileAssistantPromptsTitle),
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
                    readOnly: isBuiltin,
                    enabled: !isBuiltin,
                    keyboardType: TextInputType.multiline,
                    errorText: error,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ),
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
                  builder: (value, onChanged, error) => RevericTextField(
                    controller: promptCtrl,
                    multiline: true,
                    minLines: 8,
                    maxLines: 18,
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
