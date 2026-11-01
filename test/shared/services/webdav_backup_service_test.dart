// 职责: 验证 WebDAV 连接测试使用配置中的密码原样传递，并映射鉴权错误。
// 关联文件:
//   lib/shared/services/webdav_backup_service.dart
//   lib/shared/services/webdav_transport.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/webdav_backup_config.dart';
import 'package:reveric/shared/services/webdav_backup_service.dart';
import 'package:reveric/shared/services/webdav_transport.dart';

void main() {
  const config = WebDavBackupConfig(
    enabled: true,
    serverUrl: 'https://dav.example.com',
    username: 'author',
    password: ' secret ',
  );

  test('tests with the configured password without trimming it', () async {
    final transport = _RecordingTransport();
    final service = WebDavBackupService(transport: transport);

    final result = await service.test(config);

    expect(result.success, isTrue);
    expect(transport.passwords, [' secret ', ' secret ']);
  });

  test('maps rejected credentials to unauthorized', () async {
    final service = WebDavBackupService(
      transport: _RecordingTransport(
        failure: const WebDavTransportException(statusCode: 401),
      ),
    );

    final result = await service.test(config);

    expect(result.success, isFalse);
    expect(result.failureReason, WebDavFailureReason.unauthorized);
  });

  test('rejects an enabled config without a password', () async {
    final transport = _RecordingTransport();
    final service = WebDavBackupService(transport: transport);

    final result = await service.test(config.copyWith(password: ''));

    expect(
      config.copyWith(password: '').validate(),
      WebDavConfigIssue.missingPassword,
    );
    expect(result.failureReason, WebDavFailureReason.invalidConfiguration);
    expect(transport.passwords, isEmpty);
  });
}

class _RecordingTransport extends WebDavTransport {
  _RecordingTransport({this.failure});

  final WebDavTransportException? failure;
  final passwords = <String>[];

  @override
  Future<void> ensureDirectory({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
  }) async {
    passwords.add(credentials.password);
    if (failure != null) throw failure!;
  }

  @override
  Future<List<WebDavBackupFile>> listBackups({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
  }) async {
    passwords.add(credentials.password);
    if (failure != null) throw failure!;
    return const <WebDavBackupFile>[];
  }
}
