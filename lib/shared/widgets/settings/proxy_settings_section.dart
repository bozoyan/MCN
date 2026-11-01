// 职责: 编辑并保存模型下载与更新检查使用的代理设置（模式、地址与认证信息）。
// 关联文件:
//   lib/shared/models/network_proxy.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/settings/general_settings_section.dart
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_select.dart';
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/network_proxy.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import 'settings_section_widgets.dart';

class ProxySettingsSection extends ConsumerWidget {
  const ProxySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return settings.when(
      data: (value) => ProxySettingsForm(
        config: value.networkProxy,
        onSave: ref.read(appSettingsProvider.notifier).setNetworkProxy,
      ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(context.t(LocaleKeys.settingsProxyLoadFailed)),
    );
  }
}

enum _ProxyField implements FieldSchema {
  mode,
  url,
  username,
  password;

  @override
  List<Validator<dynamic>>? get validators => null;
}

class ProxySettingsForm extends HookWidget {
  const ProxySettingsForm({
    super.key,
    required this.config,
    required this.onSave,
  });
  final NetworkProxy config;
  final Future<void> Function(NetworkProxy) onSave;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final saving = useState(false);
    final feedback = useState<String?>(null);
    final form = useForm<_ProxyField>(
      initialValues: {
        _ProxyField.mode: config.mode,
        _ProxyField.url: config.url,
        _ProxyField.username: config.username,
        _ProxyField.password: config.password,
      },
      keys: [config.encode()],
    );
    final custom =
        form.getValue<NetworkProxyMode>(_ProxyField.mode) ==
        NetworkProxyMode.custom;

    ({
      NetworkProxyCredentialError? username,
      NetworkProxyCredentialError? password,
    })
    credentialErrors() => NetworkProxy.credentialFieldErrors(
      address: form.getValue<String>(_ProxyField.url) ?? '',
      username: form.getValue<String>(_ProxyField.username) ?? '',
      password: form.getValue<String>(_ProxyField.password) ?? '',
    );

    Future<void> save() async {
      if (saving.value) {
        return;
      }
      feedback.value = null;
      if (!form.validate()) {
        return;
      }
      final next = NetworkProxy(
        mode: form.getValue<NetworkProxyMode>(_ProxyField.mode)!,
        url: form.getValue<String>(_ProxyField.url)!.trim(),
        username: form.getValue<String>(_ProxyField.username)!,
        password: form.getValue<String>(_ProxyField.password)!,
      );
      saving.value = true;
      try {
        await onSave(next);
        if (context.mounted) {
          feedback.value = LocaleKeys.commonSaved;
        }
      } catch (_) {
        if (context.mounted) {
          feedback.value = LocaleKeys.commonSaveFailed;
        }
      } finally {
        if (context.mounted) {
          saving.value = false;
        }
      }
    }

    return HookedForm(
      form: form,
      child: SettingsSection(
        titleKey: LocaleKeys.settingsProxyTitle,
        descriptionKey: LocaleKeys.settingsProxyDescription,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  labelKey: LocaleKeys.settingsProxyMode,
                  child: HookedFormField<_ProxyField, NetworkProxyMode>(
                    fieldHook: _ProxyField.mode,
                    notifyOnChange: true,
                    builder: (value, onChanged, _) =>
                        RevericSelect<NetworkProxyMode>(
                          value: value,
                          enabled: !saving.value,
                          items: [
                            for (final mode in NetworkProxyMode.values)
                              RevericSelectItem(
                                value: mode,
                                label: context.t(switch (mode) {
                                  NetworkProxyMode.direct =>
                                    LocaleKeys.settingsProxyDirect,
                                  NetworkProxyMode.environment =>
                                    LocaleKeys.settingsProxyEnvironment,
                                  NetworkProxyMode.custom =>
                                    LocaleKeys.settingsProxyCustom,
                                }),
                              ),
                          ],
                          onChanged: (value) {
                            form.clearForcedErrors();
                            feedback.value = null;
                            onChanged?.call(value);
                          },
                        ),
                  ),
                ),
                // 非自定义模式也保留地址字段状态，切回时不丢输入。
                Visibility(
                  visible: custom,
                  maintainState: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsRowDivider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: RevericSpacing.md,
                        ),
                        child: HookedTextFormField<_ProxyField>(
                          fieldHook: _ProxyField.url,
                          label: context.t(LocaleKeys.settingsProxyAddress),
                          hintText: 'http://127.0.0.1:7890',
                          helperText: context.t(
                            LocaleKeys.settingsProxyAddressHint,
                          ),
                          enabled: !saving.value,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.url,
                          validator: (value) =>
                              custom &&
                                  NetworkProxy.parseAddress(value ?? '') == null
                              ? context.t(LocaleKeys.settingsProxyInvalidUrl)
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: RevericSpacing.md,
                        ),
                        child: _CredentialFields(
                          username: HookedTextFormField<_ProxyField>(
                            fieldHook: _ProxyField.username,
                            label: context.t(LocaleKeys.settingsProxyUsername),
                            hintText: context.t(
                              LocaleKeys.settingsProxyCredentialHint,
                            ),
                            enabled: !saving.value,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.username],
                            validator: (_) => custom
                                ? networkProxyCredentialErrorText(
                                    context,
                                    credentialErrors().username,
                                    username: true,
                                  )
                                : null,
                          ),
                          password: HookedTextFormField<_ProxyField>(
                            fieldHook: _ProxyField.password,
                            label: context.t(LocaleKeys.settingsProxyPassword),
                            hintText: context.t(
                              LocaleKeys.settingsProxyCredentialHint,
                            ),
                            enabled: !saving.value,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.password],
                            validator: (_) => custom
                                ? networkProxyCredentialErrorText(
                                    context,
                                    credentialErrors().password,
                                    username: false,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            // 保存反馈与按钮同行，出现或消失时不挤动下方内容。
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (feedback.value != null) ...[
                  Flexible(
                    child: Text(
                      context.t(feedback.value!),
                      textAlign: TextAlign.end,
                      style: typo.uiSmall.copyWith(
                        color: feedback.value == LocaleKeys.commonSaveFailed
                            ? colors.error
                            : colors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                ],
                RevericButton.primary(
                  label: context.t(LocaleKeys.commonSave),
                  loading: saving.value,
                  onPressed: save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 代理认证信息的校验错误文案；全局代理与 AI 供应商代理共用。
String? networkProxyCredentialErrorText(
  BuildContext context,
  NetworkProxyCredentialError? error, {
  required bool username,
}) => switch (error) {
  null => null,
  NetworkProxyCredentialError.incomplete => context.t(
    LocaleKeys.settingsProxyCredentialsIncomplete,
  ),
  NetworkProxyCredentialError.invalidCharacter => context.t(
    username
        ? LocaleKeys.settingsProxyUsernameInvalid
        : LocaleKeys.settingsProxyPasswordInvalid,
  ),
  NetworkProxyCredentialError.tooLong => context.t(
    LocaleKeys.settingsProxyCredentialTooLong,
  ),
};

/// 用户名与密码：宽度足够时并排，窄屏时上下排列。
class _CredentialFields extends StatelessWidget {
  const _CredentialFields({required this.username, required this.password});

  static const _sideBySideMinWidth = 480.0;

  final Widget username;
  final Widget password;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              username,
              const SizedBox(height: RevericSpacing.lg),
              password,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: username),
            const SizedBox(width: RevericSpacing.lg),
            Expanded(child: password),
          ],
        );
      },
    );
  }
}
