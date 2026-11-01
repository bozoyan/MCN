// 职责: 桌面存储设置页 — 选择本地存储目录并即时迁移，配置 S3 对象存储。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/object_storage_form.dart
//   lib/shared/services/file_workspace_orchestrator.dart
//   lib/shared/widgets/file_workspace_startup_gate.dart
//   lib/shared/providers/object_storage.dart
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/file-access.md

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/object_storage.dart';
import '../../../shared/services/file_workspace_orchestrator.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/file_workspace_startup_gate.dart';
import '../../../shared/widgets/settings/object_storage_form.dart';
import '../../../shared/widgets/settings/settings_section_widgets.dart';

class StorageSettingsSection extends HookConsumerWidget {
  const StorageSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final config = ref.watch(objectStorageConfigProvider);
    final revision = useState(0);
    final location = useFuture(
      useMemoized(() => FileWorkspaceOrchestrator().load(), [revision.value]),
    );
    final target = useTextEditingController();
    final hasTarget = useListenableSelector(
      target,
      () => target.text.trim().isNotEmpty,
    );
    final busy = useState(false);
    final failed = useState(false);

    Future<void> choose() async {
      try {
        final path = await getDirectoryPath(canCreateDirectories: true);
        if (path != null && context.mounted) {
          target.text = path;
          failed.value = false;
        }
      } catch (error, stack) {
        logFileWorkspaceError('select', error, stack);
        if (context.mounted) {
          failed.value = true;
        }
      }
    }

    // 设置页只校验目标，复制与切换由启动门在卸载业务树后完成。
    Future<void> migrate() async {
      final path = target.text.trim();
      if (busy.value || path.isEmpty) {
        return;
      }
      busy.value = true;
      failed.value = false;
      try {
        final parent = await FileWorkspaceOrchestrator().prepare(path);
        if (!context.mounted) {
          return;
        }
        if (parent == null) {
          target.clear();
          return;
        }
        FileWorkspaceStartupGate.migrate(context, parent);
      } catch (error, stack) {
        logFileWorkspaceError('select/save', error, stack);
        if (context.mounted) {
          failed.value = true;
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    final current = location.data;
    final ready = location.connectionState == ConnectionState.done;
    final labelStyle = typo.uiSmall.copyWith(color: colors.textMuted);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t(LocaleKeys.settingsStorage), style: typo.heading2),
          const SizedBox(height: RevericSpacing.x3l),
          SettingsSection(
            titleKey: LocaleKeys.settingsFileWorkspaceDirectory,
            descriptionKey: LocaleKeys.settingsFileWorkspaceHint,
            child: SettingsCard(
              children: [
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  context.t(LocaleKeys.settingsFileWorkspaceCurrent),
                  style: labelStyle,
                ),
                const SizedBox(height: RevericSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: current == null
                          ? const SizedBox.shrink()
                          : SelectableText(
                              current.currentDirectory,
                              key: const ValueKey('file_workspace_current'),
                              style: typo.ui.copyWith(
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                            ),
                    ),
                    if (location.hasError)
                      RevericButton.text(
                        label: context.t(LocaleKeys.commonRetry),
                        size: RevericButtonSize.compact,
                        onPressed: () => revision.value++,
                      ),
                  ],
                ),
                const SizedBox(height: RevericSpacing.md),
                const SettingsRowDivider(),
                const SizedBox(height: RevericSpacing.md),
                Text(
                  context.t(LocaleKeys.settingsFileWorkspaceTarget),
                  style: labelStyle,
                ),
                const SizedBox(height: RevericSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: RevericTextField(
                        controller: target,
                        fieldKey: const ValueKey('file_workspace_target'),
                        hintText: context.t(
                          LocaleKeys.settingsFileWorkspaceTargetHint,
                        ),
                        enabled: !busy.value,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (_) => failed.value = false,
                        onSubmitted: (_) => migrate(),
                      ),
                    ),
                    const SizedBox(width: RevericSpacing.md),
                    RevericButton.secondary(
                      key: const ValueKey('file_workspace_choose'),
                      label: context.t(LocaleKeys.commonChoose),
                      icon: RevericIcons.folder_outlined,
                      onPressed: busy.value ? null : choose,
                    ),
                  ],
                ),
                const SizedBox(height: RevericSpacing.md),
                Text(
                  context.t(
                    failed.value
                        ? LocaleKeys.settingsFileWorkspaceSaveFailed
                        : location.hasError
                        ? LocaleKeys.settingsFileWorkspaceLoadFailed
                        : LocaleKeys.settingsFileWorkspaceMigrateHint,
                  ),
                  style: failed.value || location.hasError
                      ? labelStyle.copyWith(color: colors.deletionBorder)
                      : labelStyle,
                ),
                const SizedBox(height: RevericSpacing.lg),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: RevericButton.primary(
                    key: const ValueKey('file_workspace_migrate'),
                    label: context.t(LocaleKeys.settingsFileWorkspaceMigrate),
                    loading: busy.value,
                    onPressed: ready && current != null && hasTarget
                        ? migrate
                        : null,
                  ),
                ),
                const SizedBox(height: RevericSpacing.xxs),
              ],
            ),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          SettingsSection(
            titleKey: LocaleKeys.settingsObjectStorageTitle,
            descriptionKey: LocaleKeys.settingsStorageDescription,
            child: SettingsCard(
              children: [
                const SizedBox(height: RevericSpacing.sm),
                if (config.asData?.value case final value?)
                  ObjectStorageForm(config: value),
                const SizedBox(height: RevericSpacing.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
