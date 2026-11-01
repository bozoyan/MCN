// 职责: 验证本地备份与 WebDAV 上传的编排结果。
// 关联文件:
//   lib/shared/services/backup_orchestrator.dart
//   lib/shared/services/backup_service.dart
//   lib/shared/services/webdav_backup_service.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/webdav_backup_config.dart';
import 'package:reveric/shared/services/backup_orchestrator.dart';
import 'package:reveric/shared/services/backup_service.dart';
import 'package:reveric/shared/services/webdav_backup_service.dart';
import 'package:reveric/shared/services/webdav_transport.dart';

void main() {
  const config = WebDavBackupConfig(
    enabled: true,
    serverUrl: 'https://dav.example.com',
    username: 'author',
  );

  for (final temporary in [false, true]) {
    test('disabled WebDAV skips upload (temporary=$temporary)', () async {
      final remote = _FakeWebDavBackupService(
        const WebDavOperationResult.failure(
          WebDavFailureReason.connectionFailed,
        ),
      );
      final orchestrator = BackupOrchestrator(
        backupService: _FakeBackupService(),
        webDavBackupService: remote,
      );
      final disabled = config.copyWith(enabled: false);
      final result = temporary
          ? await orchestrator.createTemporaryBackup(webDavConfig: disabled)
          : await orchestrator.createBackup(
              outputDirectory: '/local',
              webDavConfig: disabled,
            );
      expect(result.success, isTrue);
      expect(result.backupPath, '/local/reveric_backup.zip');
      expect(remote.uploadCount, 0);
      // The same failing remote is reached when uploading is enabled.
      final enabledResult = await orchestrator.createBackup(
        outputDirectory: '/local',
        webDavConfig: config,
      );
      expect(
        enabledResult.failureReason,
        BackupFailureReason.webDavUploadFailed,
      );
      expect(remote.uploadCount, 1);
    });
  }

  test('keeps the local path when WebDAV upload fails', () async {
    final result = await BackupOrchestrator(
      backupService: _FakeBackupService(),
      webDavBackupService: _FakeWebDavBackupService(
        const WebDavOperationResult.failure(
          WebDavFailureReason.connectionFailed,
        ),
      ),
    ).createBackup(outputDirectory: '/local', webDavConfig: config);

    expect(result.success, isFalse);
    expect(result.failureReason, BackupFailureReason.webDavUploadFailed);
    expect(result.backupPath, '/local/reveric_backup.zip');
  });

  test('returns local success after WebDAV upload succeeds', () async {
    final result = await BackupOrchestrator(
      backupService: _FakeBackupService(),
      webDavBackupService: _FakeWebDavBackupService(
        const WebDavOperationResult.success(),
      ),
    ).createBackup(outputDirectory: '/local', webDavConfig: config);

    expect(result.success, isTrue);
    expect(result.backupPath, '/local/reveric_backup.zip');
  });
}

class _FakeBackupService extends BackupService {
  @override
  Future<BackupResult> backupToTemporaryZip() => backupToZip();

  @override
  Future<BackupResult> backupToZip({String? outputDirectory}) async {
    return const BackupResult(
      success: true,
      backupPath: '/local/reveric_backup.zip',
    );
  }
}

class _FakeWebDavBackupService extends WebDavBackupService {
  _FakeWebDavBackupService(this.result)
    : super(transport: const WebDavTransport());

  final WebDavOperationResult result;
  int uploadCount = 0;

  @override
  Future<WebDavOperationResult> uploadBackup({
    required WebDavBackupConfig config,
    required String localPath,
  }) async {
    uploadCount++;
    return result;
  }
}
