// 职责: 展示本机 Codex 文件登录态及重新检测入口。
// 关联文件:
//   lib/shared/services/ai/codex/credentials.dart
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:http/http.dart' as http;

import '../../components/reveric_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/ai_provider.dart';
import '../../services/ai/codex/credentials.dart';
import '../../theme/theme.dart';

String codexAuthErrorKey(CodexAuthException error) => switch (error.reason) {
  CodexAuthFailure.unsupported_platform => LocaleKeys.settingsCodexDesktopOnly,
  CodexAuthFailure.missing => LocaleKeys.settingsCodexAuthMissing,
  CodexAuthFailure.invalid => LocaleKeys.settingsCodexAuthInvalid,
  CodexAuthFailure.expired => LocaleKeys.settingsCodexAuthExpired,
  CodexAuthFailure.refresh_failed => LocaleKeys.settingsCodexAuthRefreshFailed,
  CodexAuthFailure.write_failed => LocaleKeys.settingsCodexAuthWriteFailed,
  CodexAuthFailure.changed => LocaleKeys.settingsCodexAuthChanged,
};

class CodexConnection extends HookWidget {
  const CodexConnection({
    super.key,
    required this.config,
    this.loadCredentials = CodexCredentials.load,
  });

  final AiProvider config;
  final Future<CodexCredentials> Function({http.Client? client})
  loadCredentials;

  @override
  Widget build(BuildContext context) {
    final revision = useState(0);
    // 检测时可能刷新 token，必须走供应商配置的代理。
    final request = useMemoized(
      () async {
        final client = config.createProxyClient();
        try {
          return await loadCredentials(client: client);
        } finally {
          client?.close();
        }
      },
      [
        loadCredentials,
        revision.value,
        config.proxyUrl,
        config.proxyUsername,
        config.proxyPassword,
      ],
    );
    final snapshot = useFuture(request);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final loading = snapshot.connectionState != ConnectionState.done;
    final error = snapshot.error;
    final status = loading
        ? LocaleKeys.settingsCodexChecking
        : error is CodexAuthException
        ? codexAuthErrorKey(error)
        : error != null
        ? LocaleKeys.settingsCodexAuthInvalid
        : LocaleKeys.settingsCodexAuthReady;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(status),
          style: typo.ui.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.sm),
        Text(
          context.t(LocaleKeys.settingsCodexAuthHint),
          style: typo.uiSmall.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.sm),
        if (CodexCredentials.supportedPlatform)
          RevericButton.secondary(
            label: context.t(LocaleKeys.settingsCodexCheckLogin),
            loading: loading,
            onPressed: () => revision.value++,
          ),
      ],
    );
  }
}
