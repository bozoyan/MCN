// 职责: WebDAV 备份设置区，编辑并保存连接配置、测试连接。
// 关联文件:
//   lib/shared/models/webdav_backup_config.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/webdav_backup_providers.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_switch.dart';
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/webdav_backup_config.dart';
import '../../providers/settings_providers.dart';
import '../../providers/webdav_backup_providers.dart';
import '../../services/webdav_backup_service.dart';
import '../../theme/theme.dart';

enum _WebDavField implements FieldSchema {
  serverUrl,
  username,
  password,
  remoteDirectory;

  @override
  List<Validator<dynamic>>? get validators => null;
}

class WebDavBackupSettings extends HookConsumerWidget {
  const WebDavBackupSettings({
    super.key,
    required this.config,
    required this.compact,
  });

  final WebDavBackupConfig config;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final enabled = useState(config.enabled);
    final obscurePassword = useState(true);
    final isSaving = useState(false);
    final feedback = useState<String?>(null);
    final feedbackIsError = useState(false);
    final service = ref.watch(webDavBackupServiceProvider);
    final form = useForm<_WebDavField>(
      initialValues: <_WebDavField, dynamic>{
        _WebDavField.serverUrl: config.serverUrl,
        _WebDavField.username: config.username,
        _WebDavField.password: config.password,
        _WebDavField.remoteDirectory: config.remoteDirectory,
      },
      keys: <Object?>[
        config.serverUrl,
        config.username,
        config.password,
        config.remoteDirectory,
      ],
    );
    final serverUrl = form.getValue<String>(_WebDavField.serverUrl);
    final usesHttp = _usesHttp(serverUrl);

    Future<void> disable() async {
      if (isSaving.value) {
        return;
      }
      isSaving.value = true;
      feedback.value = null;
      try {
        // 关闭立即生效，只修改已保存配置的开关，不提交未完成的连接编辑。
        await ref
            .read(appSettingsNotifierProvider.notifier)
            .setWebDavBackupConfig(config.copyWith(enabled: false));
        if (!context.mounted) {
          return;
        }
        enabled.value = false;
        feedback.value = context.t(LocaleKeys.settingsWebDavSaved);
        feedbackIsError.value = false;
      } catch (_) {
        if (!context.mounted) {
          return;
        }
        feedback.value = context.t(LocaleKeys.settingsWebDavSaveFailed);
        feedbackIsError.value = true;
      } finally {
        if (context.mounted) {
          isSaving.value = false;
        }
      }
    }

    Future<void> save() async {
      if (isSaving.value) return;
      feedback.value = null;
      form.clearForcedErrors();
      final nextConfig = WebDavBackupConfig(
        enabled: enabled.value,
        serverUrl: form.getValue<String>(_WebDavField.serverUrl)?.trim() ?? '',
        username: form.getValue<String>(_WebDavField.username)?.trim() ?? '',
        password: form.getValue<String>(_WebDavField.password) ?? '',
        remoteDirectory:
            form.getValue<String>(_WebDavField.remoteDirectory)?.trim() ?? '',
      ).normalized();
      if (!enabled.value) {
        await disable();
        return;
      }

      final issue = nextConfig.validate();
      if (issue != null) {
        final (field, messageKey) = switch (issue) {
          WebDavConfigIssue.invalidServerUrl => (
            _WebDavField.serverUrl,
            LocaleKeys.settingsWebDavInvalidUrl,
          ),
          WebDavConfigIssue.missingUsername => (
            _WebDavField.username,
            LocaleKeys.settingsWebDavUsernameRequired,
          ),
          WebDavConfigIssue.missingPassword => (
            _WebDavField.password,
            LocaleKeys.settingsWebDavPasswordRequired,
          ),
          WebDavConfigIssue.invalidRemoteDirectory => (
            _WebDavField.remoteDirectory,
            LocaleKeys.settingsWebDavRemoteDirectoryInvalid,
          ),
        };
        form.setError(field, context.t(messageKey));
        return;
      }

      isSaving.value = true;
      try {
        final result = await service.test(nextConfig);
        if (!context.mounted) return;
        if (!result.success) {
          feedback.value = _failureMessage(context, result.failureReason);
          feedbackIsError.value = true;
          return;
        }
        await ref
            .read(appSettingsNotifierProvider.notifier)
            .setWebDavBackupConfig(nextConfig);
        if (!context.mounted) return;
        feedback.value = context.t(LocaleKeys.settingsWebDavSaved);
        feedbackIsError.value = false;
      } catch (_) {
        if (!context.mounted) return;
        feedback.value = context.t(LocaleKeys.settingsWebDavSaveFailed);
        feedbackIsError.value = true;
      } finally {
        if (context.mounted) {
          isSaving.value = false;
        }
      }
    }

    Future<void> changeEnabled(bool value) async {
      if (isSaving.value) {
        return;
      }
      if (!value) {
        await disable();
        return;
      }
      enabled.value = true;
      feedback.value = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.settingsWebDavTitle),
          style: compact
              ? typo.uiSemibold.copyWith(color: colors.textPrimary)
              : typo.heading2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.settingsWebDavDescription),
          style: (compact ? typo.uiSmall : typo.ui).copyWith(
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: RevericSpacing.md),
        Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            side: BorderSide(color: colors.borderSubtle),
          ),
          child: MergeSemantics(
            child: ListTile(
              onTap: isSaving.value
                  ? null
                  : () => changeEnabled(!enabled.value),
              leading: RevericIcon(
                enabled.value
                    ? RevericIcons.cloud_upload
                    : RevericIcons.cloud_off,
                size: 20,
                color: colors.textSecondary,
              ),
              title: Text(
                context.t(LocaleKeys.settingsWebDavEnable),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              trailing: RevericSwitch(
                key: const ValueKey('webdav_enabled_switch'),
                value: enabled.value,
                onChanged: isSaving.value ? null : changeEnabled,
              ),
            ),
          ),
        ),
        if (enabled.value) ...[
          const SizedBox(height: RevericSpacing.lg),
          HookedForm<_WebDavField>(
            form: form,
            child: Column(
              children: [
                HookedTextFormField<_WebDavField>(
                  key: const ValueKey('webdav_server_url_field'),
                  fieldHook: _WebDavField.serverUrl,
                  notifyOnChange: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  label: context.t(LocaleKeys.settingsWebDavServerUrl),
                  hintText: context.t(LocaleKeys.settingsWebDavServerUrlHint),
                ),
                if (usesHttp) ...[
                  const SizedBox(height: RevericSpacing.sm),
                  _WebDavHttpWarning(
                    message: context.t(LocaleKeys.settingsWebDavHttpWarning),
                  ),
                ],
                const SizedBox(height: RevericSpacing.md),
                HookedTextFormField<_WebDavField>(
                  key: const ValueKey('webdav_username_field'),
                  fieldHook: _WebDavField.username,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[AutofillHints.username],
                  label: context.t(LocaleKeys.settingsWebDavUsername),
                ),
                const SizedBox(height: RevericSpacing.md),
                HookedTextFormField<_WebDavField>(
                  key: const ValueKey('webdav_password_field'),
                  fieldHook: _WebDavField.password,
                  obscureText: obscurePassword.value,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[AutofillHints.password],
                  label: context.t(LocaleKeys.settingsWebDavPassword),
                  suffixIcon: IconButton(
                    onPressed: () {
                      obscurePassword.value = !obscurePassword.value;
                    },
                    icon: RevericIcon(
                      obscurePassword.value
                          ? RevericIcons.visibility
                          : RevericIcons.visibility_off,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.md),
                HookedTextFormField<_WebDavField>(
                  key: const ValueKey('webdav_remote_directory_field'),
                  fieldHook: _WebDavField.remoteDirectory,
                  autocorrect: false,
                  enableSuggestions: false,
                  label: context.t(LocaleKeys.settingsWebDavRemoteDirectory),
                ),
              ],
            ),
          ),
        ],
        if (enabled.value) ...[
          const SizedBox(height: RevericSpacing.md),
          RevericButton.primary(
            key: const ValueKey('webdav_save_button'),
            onPressed: save,
            loading: isSaving.value,
            icon: RevericIcons.cloud_upload,
            label: context.t(
              isSaving.value
                  ? LocaleKeys.settingsWebDavSaving
                  : LocaleKeys.settingsWebDavSaveAndTest,
            ),
          ),
        ],
        if (feedback.value != null) ...[
          const SizedBox(height: RevericSpacing.md),
          _WebDavFeedback(
            message: feedback.value!,
            isError: feedbackIsError.value,
          ),
        ],
      ],
    );
  }
}

bool _usesHttp(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  return uri != null &&
      uri.scheme.toLowerCase() == 'http' &&
      uri.host.isNotEmpty;
}

String _failureMessage(BuildContext context, WebDavFailureReason? reason) {
  return switch (reason) {
    WebDavFailureReason.unauthorized => context.t(
      LocaleKeys.settingsWebDavUnauthorized,
    ),
    WebDavFailureReason.connectionFailed => context.t(
      LocaleKeys.settingsWebDavConnectionFailed,
    ),
    WebDavFailureReason.credentialUnavailable => context.t(
      LocaleKeys.settingsWebDavPasswordRequired,
    ),
    _ => context.t(LocaleKeys.settingsWebDavSaveFailed),
  };
}

class _WebDavHttpWarning extends StatelessWidget {
  const _WebDavHttpWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericIcon(
            RevericIcons.warning_amber_rounded,
            size: 18,
            color: colors.warningText,
          ),
          const SizedBox(width: RevericSpacing.sm),
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

class _WebDavFeedback extends StatelessWidget {
  const _WebDavFeedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final color = isError ? colors.deletionBorder : colors.additionBorder;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.md),
      decoration: BoxDecoration(
        color: isError ? colors.deletionBg : colors.additionBg,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: Row(
        children: [
          RevericIcon(
            isError ? RevericIcons.error_outline : RevericIcons.check_circle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(message, style: typo.uiSmall.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
