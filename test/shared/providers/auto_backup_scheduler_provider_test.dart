// 职责: 验证自动备份 Provider — 预热后会读取持久化计划、执行备份并回写完成时间，且移动端一律不调度。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/shared/services/auto_backup_scheduler.dart
//   lib/shared/services/backup_service.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/testing.md

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/app_settings_aggregate_data.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/backup_service.dart';

void main() {
  // appSettingsProvider 会连带唤醒 account/novel provider 链，其中的真实 AppDatabase
  // 走 drift_flutter，需要 path_provider 平台通道；缺少它整个测试会直接抛异常失败。
  TestWidgetsFlutterBinding.ensureInitialized();
  final pathProviderRoot = Directory.systemTemp.createTempSync(
    'auto_backup_scheduler_provider_test',
  );
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => pathProviderRoot.path,
        );
  });
  tearDownAll(() {
    pathProviderRoot.deleteSync(recursive: true);
  });

  test(
    'preheating the provider runs a due backup and persists completion',
    () async {
      // flutter_test 默认把 defaultTargetPlatform 设为 android，而自动备份只在桌面可用。
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final database = AppDatabase.forTest(NativeDatabase.memory());
      await database.appSettingsDao.set(
        key: StorageSettingsData.appSettingsKey,
        value: const StorageSettingsData(
          changeRecordRetentionDays: 30,
          backupDirectory: '/tmp/backups',
          backupFrequency: 'weekly',
          backupWeekdays: <int>[DateTime.monday],
          backupDayOfMonth: 1,
          backupHour: 2,
          backupMinute: 0,
        ).encode(),
      );
      await database.appSettingsDao.set(
        key: 'last_backup_time',
        value: DateTime(2000).toIso8601String(),
      );
      final backupService = _RecordingBackupService();
      final container = ProviderContainer(
        overrides: [
          appSettingsDatabaseProvider.overrideWithValue(database),
          backupServiceProvider.overrideWithValue(backupService),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appSettingsProvider.future);
      final scheduler = container.read(autoBackupSchedulerProvider);
      await backupService.started.future.timeout(const Duration(seconds: 2));
      await Future.doWhile(() async {
        if (!scheduler.isRunning) {
          return false;
        }
        await Future<void>.delayed(Duration.zero);
        return true;
      }).timeout(const Duration(seconds: 2));

      expect(backupService.outputDirectories, ['/tmp/backups']);
      final persisted = await database.appSettingsDao.get('last_backup_time');
      expect(DateTime.tryParse(persisted ?? ''), isNotNull);
      expect(DateTime.parse(persisted!).isAfter(DateTime(2000)), isTrue);
    },
  );

  test('a due schedule never runs on mobile because backups cannot be written '
      'to a user-chosen directory there', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final database = AppDatabase.forTest(NativeDatabase.memory());
    await database.appSettingsDao.set(
      key: StorageSettingsData.appSettingsKey,
      value: const StorageSettingsData(
        changeRecordRetentionDays: 30,
        backupDirectory: '/storage/emulated/0/backups',
        backupFrequency: 'daily',
        backupWeekdays: <int>[DateTime.monday],
        backupDayOfMonth: 1,
        backupHour: 2,
        backupMinute: 0,
      ).encode(),
    );
    await database.appSettingsDao.set(
      key: 'last_backup_time',
      value: DateTime(2000).toIso8601String(),
    );
    final backupService = _RecordingBackupService();
    final container = ProviderContainer(
      overrides: [
        appSettingsDatabaseProvider.overrideWithValue(database),
        backupServiceProvider.overrideWithValue(backupService),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await container.read(appSettingsProvider.future);
    final scheduler = container.read(autoBackupSchedulerProvider);
    expect(await scheduler.checkNow(), isFalse);

    expect(backupService.outputDirectories, isEmpty);
    final persisted = await database.appSettingsDao.get('last_backup_time');
    expect(DateTime.parse(persisted!), DateTime(2000));
  });
}

class _RecordingBackupService extends BackupService {
  final started = Completer<void>();
  final outputDirectories = <String>[];

  @override
  Future<BackupResult> backupToZip({String? outputDirectory}) async {
    outputDirectories.add(outputDirectory ?? '');
    if (!started.isCompleted) {
      started.complete();
    }
    return const BackupResult(success: true);
  }
}
