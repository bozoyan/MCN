// 职责: 从 GitHub Releases 获取最新版本并选择匹配平台和架构的更新包
// 关联文件:
//   lib/shared/services/update/models.dart
//   lib/shared/services/update/update_source.dart
//   lib/shared/logger/log_manager.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../logger/app_logger.dart';
import '../../../localization/locale_keys.dart';
import '../models.dart';
import '../update_source.dart';

final _log = AppLogger.forModule('GitHubReleases');

/// GitHub Releases 更新源
class GitHubReleasesSource implements UpdateSource {
  final FutureOr<http.Client> Function() createClient;
  final String owner;
  final String repo;
  final String? apiToken;
  final String _operatingSystem;
  final Abi _abi;

  GitHubReleasesSource({
    required this.owner,
    required this.repo,
    this.apiToken,
    this.createClient = http.Client.new,
    String? operatingSystem,
    Abi? abi,
  }) : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _abi = abi ?? Abi.current();

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    http.Client? client;
    try {
      client = await createClient();
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );

      final headers = <String, String>{'Accept': 'application/vnd.github+json'};
      if (apiToken != null) {
        headers['Authorization'] = 'Bearer $apiToken';
      }

      _log.info(
        'GitHub release check owner=$owner repo=$repo currentVersion=$currentVersion',
      );

      final response = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 403) {
        return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
      }
      if (response.statusCode == 404) {
        return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
      }
      if (response.statusCode != 200) {
        return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = body['tag_name'] as String? ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;

      if (!isNewerVersion(latestVersion, currentVersion)) {
        return const UpdateUpToDate();
      }

      final asset = _findPlatformAsset(body['assets'] as List<dynamic>?);
      if (asset == null) {
        return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
      }

      return UpdateAvailable(
        UpdateInfo(
          version: latestVersion,
          downloadUrl: asset['browser_download_url'] as String,
          fileSize: asset['size'] as int?,
          releaseNotes: body['body'] as String?,
        ),
      );
    } catch (e) {
      _log.warning('GitHub release check failed error=$e');
      return const UpdateCheckFailed(LocaleKeys.settingsAboutCheckFailed);
    } finally {
      client?.close();
    }
  }

  Map<String, dynamic>? _findPlatformAsset(List<dynamic>? assets) {
    if (assets == null || assets.isEmpty) {
      return null;
    }

    final patterns = _platformAssetPatterns();
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (!_isSupportedUpdateAsset(name)) {
        continue;
      }
      for (final pattern in patterns) {
        if (name.contains(pattern)) {
          return asset;
        }
      }
      if (_operatingSystem == 'windows' && _isSupportedUpdateAsset(name)) {
        return asset;
      }
    }
    return null;
  }

  bool _isSupportedUpdateAsset(String name) {
    if (_operatingSystem == 'macos') {
      final architecture = switch (_abi) {
        Abi.macosArm64 => 'arm64',
        Abi.macosX64 => 'x86_64',
        _ => null,
      };
      return architecture != null && name.endsWith('-macos-$architecture.zip');
    }
    if (_operatingSystem == 'windows') {
      // Windows 更新使用 Inno Setup 安装器：安装目录可能需要 UAC，且安装器会处理
      // VC++ redistributable、关闭旧进程和替换完整 Flutter bundle。
      return name.endsWith('.exe') && name.contains('setup');
    }
    if (_operatingSystem == 'android') {
      return name.endsWith('.apk') && name.contains('arm64-v8a');
    }
    return name.endsWith('.zip');
  }

  List<String> _platformAssetPatterns() {
    return switch (_operatingSystem) {
      'macos' => ['macos'],
      'windows' => ['windows', 'win'],
      'linux' => ['linux', 'ubuntu', 'appimage'],
      'android' => ['arm64-v8a', 'android', 'apk'],
      _ => [],
    };
  }
}
