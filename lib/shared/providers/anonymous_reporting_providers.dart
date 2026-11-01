// 职责: 装配匿名 Outbox 与用户上报同意状态的全局 Provider。
// 关联文件:
//   lib/shared/services/anonymous_outbox_service.dart
//   lib/shared/services/anonymous_reporting_consent_service.dart
//   lib/shared/providers/device_id_providers.dart
//   lib/shared/widgets/settings/general_settings_section.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/state-management.md

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_config.dart';
import '../services/anonymous_outbox_service.dart';
import '../services/anonymous_reporting_consent_service.dart';
import 'novel_providers.dart';

part 'anonymous_reporting_providers.g.dart';

@Riverpod(keepAlive: true)
AnonymousReportingConsentService anonymousReportingConsentService(Ref ref) =>
    const AnonymousReportingConsentService();

/// 用户是否同意匿名诊断上报（opt-in，默认 false）。
@Riverpod(keepAlive: true)
class AnonymousReportingConsent extends _$AnonymousReportingConsent {
  @override
  Future<bool> build() =>
      ref.watch(anonymousReportingConsentServiceProvider).isGranted();

  Future<void> set(bool granted) async {
    await ref
        .read(anonymousReportingConsentServiceProvider)
        .setGranted(granted);
    if (ref.mounted) {
      state = AsyncValue.data(granted);
    }
  }
}

@Riverpod(keepAlive: true)
AnonymousOutboxService anonymousOutboxService(Ref ref) {
  final httpClient = http.Client();
  final service = AnonymousOutboxService(
    database: ref.watch(appDatabaseProvider),
    httpClient: httpClient,
    getBaseUrl: () => anonymousReportingBaseUrl,
    // 同意状态加载完成前按未同意处理，不上报。
    getEnabled: () =>
        anonymousReportingBaseUrl.isNotEmpty &&
        ref.read(anonymousReportingConsentProvider).value == true,
  );
  ref.onDispose(() {
    service.dispose();
    httpClient.close();
  });
  return service;
}
