// 职责: WebDAV 备份配置与远程备份文件元数据建模。
// 关联文件:
//   lib/shared/services/webdav_backup_service.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/settings/webdav_backup_settings.dart

class WebDavBackupConfig {
  const WebDavBackupConfig({
    this.enabled = false,
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDirectory = defaultRemoteDirectory,
  });

  static const defaultRemoteDirectory = '/Reveric/Backups';

  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String remoteDirectory;

  WebDavBackupConfig normalized() {
    final trimmedUrl = serverUrl.trim();
    return WebDavBackupConfig(
      enabled: enabled,
      serverUrl: trimmedUrl.isEmpty || trimmedUrl.endsWith('/')
          ? trimmedUrl
          : '$trimmedUrl/',
      username: username.trim(),
      password: password,
      remoteDirectory: normalizeWebDavRemoteDirectory(remoteDirectory),
    );
  }

  WebDavConfigIssue? validate() {
    if (!enabled) {
      return null;
    }
    final normalizedConfig = normalized();
    final uri = Uri.tryParse(normalizedConfig.serverUrl);
    final isSupportedScheme = uri?.scheme == 'http' || uri?.scheme == 'https';
    if (uri == null ||
        !isSupportedScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return WebDavConfigIssue.invalidServerUrl;
    }
    if (normalizedConfig.username.isEmpty) {
      return WebDavConfigIssue.missingUsername;
    }
    if (normalizedConfig.password.isEmpty) {
      return WebDavConfigIssue.missingPassword;
    }
    if (normalizedConfig.remoteDirectory == '/' ||
        normalizedConfig.remoteDirectory.isEmpty) {
      return WebDavConfigIssue.invalidRemoteDirectory;
    }
    final segments = normalizedConfig.remoteDirectory
        .split('/')
        .where((segment) => segment.isNotEmpty);
    if (segments.any(
      (segment) => segment == '.' || segment == '..' || segment.contains('\\'),
    )) {
      return WebDavConfigIssue.invalidRemoteDirectory;
    }
    return null;
  }

  bool get isConfigured => validate() == null && enabled;

  WebDavBackupConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDirectory,
  }) {
    return WebDavBackupConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDirectory: remoteDirectory ?? this.remoteDirectory,
    );
  }
}

enum WebDavConfigIssue {
  invalidServerUrl,
  missingUsername,
  missingPassword,
  invalidRemoteDirectory,
}

class WebDavBackupFile {
  const WebDavBackupFile({
    required this.name,
    required this.remotePath,
    required this.size,
    required this.modifiedAt,
  });

  final String name;
  final String remotePath;
  final int? size;
  final DateTime? modifiedAt;
}

String normalizeWebDavRemoteDirectory(String value) {
  final normalizedSlashes = value.trim().replaceAll('\\', '/');
  final segments = normalizedSlashes
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return '/';
  }
  return '/${segments.join('/')}';
}
