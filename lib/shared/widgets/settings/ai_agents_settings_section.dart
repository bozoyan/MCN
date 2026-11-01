// 职责: 共享 AI 助手设置区 — 工具权限、头像与身份/人格配置。
// 关联文件:
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/agent_profile.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'dart:io';
import '../../models/tool_permission.dart';
import '../ai/tool_permission_editor.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_switch.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/agent_profile.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import '../../utils/storage_paths.dart';
import '../../widgets/agent_avatar.dart';
import 'settings_section_widgets.dart';

/// AI 助手设置 section：头像 + 身份/人格 prompt，以及全局工具权限。
class AiAgentsSettingsSection extends HookConsumerWidget {
  const AiAgentsSettingsSection({super.key, this.showPermissions = true});

  /// 移动端不提供权限管理。
  final bool showPermissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(aiAgentIdentityProvider);
    final soul = ref.watch(aiAgentSoulProvider);
    final avatarPath = ref.watch(aiAgentAvatarPathProvider);
    final nextActionSuggestions = ref.watch(
      aiAgentNextActionSuggestionsProvider,
    );
    final notifier = ref.read(appSettingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            titleKey: LocaleKeys.settingsAiAgentsSection,
            descriptionKey: LocaleKeys.settingsAiAgentsDescription,
            child: SettingsCard(
              children: [
                _AiAgentAvatarRow(
                  avatarPath: avatarPath,
                  onChanged: notifier.setAiAgentAvatarPath,
                ),
                const SettingsRowDivider(),
                SettingsRow(
                  labelKey: LocaleKeys.settingsAiAgentNextActionSuggestions,
                  descriptionKey: LocaleKeys
                      .settingsAiAgentNextActionSuggestionsDescription,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RevericSwitch(
                      value: nextActionSuggestions,
                      onChanged: notifier.setAiAgentNextActionSuggestions,
                    ),
                  ),
                ),
                const SettingsRowDivider(),
                _AiAgentPromptBlock(
                  labelKey: LocaleKeys.settingsAiAgentIdentity,
                  descriptionKey: LocaleKeys.settingsAiAgentIdentityDescription,
                  child: _AiAgentPromptTextField(
                    value: identity,
                    height: 160,
                    onSave: notifier.setAiAgentIdentity,
                    onReset: () {
                      notifier.setAiAgentIdentity(defaultAiAgentIdentity);
                    },
                  ),
                ),
                const SettingsRowDivider(),
                _AiAgentPromptBlock(
                  labelKey: LocaleKeys.settingsAiAgentSoul,
                  descriptionKey: LocaleKeys.settingsAiAgentSoulDescription,
                  child: _AiAgentPromptTextField(
                    value: soul,
                    height: 240,
                    onSave: notifier.setAiAgentSoul,
                    onReset: () {
                      notifier.setAiAgentSoul(defaultAiAgentSoul);
                    },
                  ),
                ),
              ],
            ),
          ),
          if (showPermissions && toolApprovalEnabled) ...[
            const SizedBox(height: RevericSpacing.x4l),
            const SettingsSection(
              titleKey: LocaleKeys.aiPermissionsTitle,
              child: SettingsCard(
                children: [
                  ToolPermissionEditor(
                    permissionContext: ToolPermissionContext(workId: ''),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiAgentAvatarRow extends HookConsumerWidget {
  const _AiAgentAvatarRow({required this.avatarPath, required this.onChanged});

  final String avatarPath;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final localPath = useState(avatarPath);

    useEffect(() {
      localPath.value = avatarPath;
      return null;
    }, [avatarPath]);

    // 存储值可能是相对/旧绝对路径；预览统一过 resolveStored 兜底。
    final resolvedLocal = RevericPaths.resolveStored(localPath.value);

    Future<void> pickAvatar() async {
      final result = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
            // iOS 要求 type group 提供 UTI，否则 file_selector 抛 Invalid argument。
            uniformTypeIdentifiers: ['public.image'],
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
        final dest = File(p.join(avatarDir.path, 'ai_agent$ext'));
        await source.copy(dest.path);
        localPath.value = dest.path;
        onChanged(RevericPaths.toRelative(dest.path) ?? dest.path);
      }
    }

    Future<void> clearAvatar() async {
      // 存储值可能是相对/旧绝对路径，先 resolve 再删，避免删不到。
      final resolved = RevericPaths.resolveStored(localPath.value);
      if (resolved != null) {
        await File(resolved).delete();
      }
      localPath.value = '';
      onChanged('');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: pickAvatar,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainer,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: ClipOval(
                child: resolvedLocal != null
                    ? Image.file(
                        File(resolvedLocal),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      )
                    : AgentAvatar(
                        slug: builtinAgentSlugOrchestrator,
                        size: 56,
                        backgroundColor: Colors.transparent,
                      ),
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.settingsAiAgentAvatar),
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  context.t(LocaleKeys.settingsAiAgentAvatarDescription),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: RevericSpacing.sm),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: pickAvatar,
                      icon: const RevericIcon(
                        RevericIcons.image_outlined,
                        size: 14,
                      ),
                      label: Text(
                        context.t(LocaleKeys.settingsAiAgentAvatarChange),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        minimumSize: const Size(0, RevericSizes.buttonHeightSm),
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.sm,
                        ),
                        textStyle: typo.uiSmall,
                      ),
                    ),
                    if (localPath.value.isNotEmpty) ...[
                      const SizedBox(width: RevericSpacing.xxs),
                      TextButton.icon(
                        onPressed: clearAvatar,
                        icon: const RevericIcon(
                          RevericIcons.delete_outline,
                          size: 14,
                        ),
                        label: Text(
                          context.t(LocaleKeys.settingsAiAgentAvatarRemove),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          minimumSize: const Size(
                            0,
                            RevericSizes.buttonHeightSm,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: RevericSpacing.sm,
                          ),
                          textStyle: typo.uiSmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAgentPromptBlock extends StatelessWidget {
  const _AiAgentPromptBlock({
    required this.labelKey,
    required this.descriptionKey,
    required this.child,
  });

  final String labelKey;
  final String descriptionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(labelKey),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.xxs),
          Text(
            context.t(descriptionKey),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _AiAgentPromptTextField extends HookWidget {
  const _AiAgentPromptTextField({
    required this.value,
    required this.height,
    required this.onSave,
    required this.onReset,
  });

  final String value;
  final double height;
  final ValueChanged<String> onSave;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final controller = useTextEditingController(text: value);
    final scrollController = useScrollController();

    useEffect(() {
      if (controller.text != value) {
        controller.value = controller.value.copyWith(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
          composing: TextRange.empty,
        );
      }
      return null;
    }, [value]);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, editingValue, child) {
        final text = editingValue.text.trim();
        final hasChanged = text != value.trim();
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            border: Border.all(
              color: hasChanged
                  ? colors.accent.withValues(alpha: 0.45)
                  : colors.borderInput,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: height,
                child: TextField(
                  controller: controller,
                  scrollController: scrollController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: typo.uiSmall.copyWith(
                    color: colors.textPrimary,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.all(RevericSpacing.md),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              Container(
                height: RevericSizes.dividerThickness,
                color: colors.borderSubtle,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                  vertical: RevericSpacing.xs,
                ),
                child: Row(
                  children: [
                    if (hasChanged) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.xs),
                    ],
                    Text(
                      editingValue.text.length.toString(),
                      style: typo.uiTiny.copyWith(
                        color: hasChanged
                            ? colors.textSecondary
                            : colors.textSubtle,
                      ),
                    ),
                    const Spacer(),
                    RevericButton.text(
                      onPressed: onReset,
                      icon: RevericIcons.undo,
                      label: context.t(LocaleKeys.commonReset),
                      size: RevericButtonSize.compact,
                    ),
                    const SizedBox(width: RevericSpacing.xxs),
                    RevericButton.primary(
                      onPressed: hasChanged ? () => onSave(text) : null,
                      icon: RevericIcons.save_outlined,
                      label: context.t(LocaleKeys.commonSave),
                      size: RevericButtonSize.compact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
