// 职责: 自定义 API 更新源 — 通过自建服务端 API 检查更新
// 关联文件:
//   lib/shared/services/update/models.dart
//   lib/shared/services/update/update_source.dart
//   lib/shared/logger/log_manager.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../logger/app_logger.dart';
import '../../../localization/locale_keys.dart';
import '../models.dart';
import '../update_source.dart';

final _log = AppLogger.forModule('CustomApiSource');

/// 自定义 API 更新源
class CustomApiSource implements UpdateSource {
  final String apiEndpoint;

  CustomApiSource(this.apiEndpoint);

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    try {
      final uri = Uri.parse(apiEndpoint).replace(
        queryParameters: {
          'platform': Platform.operatingSystem,
          'arch': Platform.operatingSystemVersion,
          'current': currentVersion,
        },
      );

      _log.info('Update check url=$uri currentVersion=$currentVersion');

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['has_update'] == true) {
        return UpdateAvailable(UpdateInfo.fromJson(body));
      }

      return const UpdateUpToDate();
    } catch (e) {
      _log.warning('Update check failed error=$e');
      return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
    }
  }
}
