// 职责: 验证自动备份调度 — 覆盖日/周/月触发时间、漏跑补做与单次执行保护。
// 关联文件:
//   lib/shared/services/auto_backup_scheduler.dart
//   lib/shared/services/backup_service.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/auto_backup_scheduler.dart';
import 'package:reveric/shared/services/backup_service.dart';

void main() {
  group('backup occurrence calculations', () {
    test('daily uses the configured local time', () {
      final schedule = _schedule(frequency: BackupFrequency.daily, hour: 2);
      final before = DateTime(2026, 8, 4, 1, 30);
      final after = DateTime(2026, 8, 4, 2, 30);

      expect(
        latestBackupOccurrenceAtOrBefore(before, schedule),
        DateTime(2026, 8, 3, 2),
      );
      expect(
        nextBackupOccurrenceAfter(before, schedule),
        DateTime(2026, 8, 4, 2),
      );
      expect(
        latestBackupOccurrenceAtOrBefore(after, schedule),
        DateTime(2026, 8, 4, 2),
      );
    });

    test('weekly uses the selected ISO weekdays and time', () {
      final schedule = _schedule(
        frequency: BackupFrequency.weekly,
        weekdays: const <int>[DateTime.tuesday, DateTime.friday],
        hour: 21,
        minute: 15,
      );
      final now = DateTime(2026, 8, 4, 12);

      expect(
        latestBackupOccurrenceAtOrBefore(now, schedule),
        DateTime(2026, 7, 31, 21, 15),
      );
      expect(
        nextBackupOccurrenceAfter(now, schedule),
        DateTime(2026, 8, 4, 21, 15),
      );
    });

    test('monthly uses the selected day and configured time', () {
      final schedule = _schedule(
        frequency: BackupFrequency.monthly,
        dayOfMonth: 17,
        hour: 6,
        minute: 30,
      );
      final now = DateTime(2026, 8, 20, 12);

      expect(
        latestBackupOccurrenceAtOrBefore(now, schedule),
        DateTime(2026, 8, 17, 6, 30),
      );
      expect(
        nextBackupOccurrenceAfter(now, schedule),
        DateTime(2026, 9, 17, 6, 30),
      );
    });
  });

  group('AutoBackupScheduler', () {
    test('runs a missed occurrence and records completion', () async {
      final now = DateTime(2026, 8, 4, 12);
      final directories = <String>[];
      final completions = <DateTime>[];
      final scheduler = AutoBackupScheduler(
        schedule: _schedule(
          frequency: BackupFrequency.daily,
          hour: 2,
          lastBackupTime: DateTime(2026, 8, 3, 2),
        ),
        executeBackup: (directory) async {
          directories.add(directory);
          return const BackupResult(success: true);
        },
        onBackupCompleted: (completedAt) async {
          completions.add(completedAt);
        },
        clock: () => now,
      );
      addTearDown(scheduler.dispose);

      expect(await scheduler.checkNow(), isTrue);
      expect(await scheduler.checkNow(), isFalse);
      expect(directories, ['/tmp/backups']);
      expect(completions, [now]);
    });

    test('does not run without an automatic frequency and directory', () async {
      var attempts = 0;
      final scheduler = AutoBackupScheduler(
        schedule: _schedule(directory: '', frequency: BackupFrequency.daily),
        executeBackup: (_) async {
          attempts += 1;
          return const BackupResult(success: true);
        },
        onBackupCompleted: (_) async {},
        clock: () => DateTime(2026, 8, 4, 12),
      );
      addTearDown(scheduler.dispose);

      expect(await scheduler.checkNow(), isFalse);
      scheduler.updateSchedule(_schedule(frequency: BackupFrequency.manual));
      expect(await scheduler.checkNow(), isFalse);
      expect(attempts, 0);
    });

    test('does not repeat a failed attempt for the same occurrence', () async {
      var attempts = 0;
      final scheduler = AutoBackupScheduler(
        schedule: _schedule(frequency: BackupFrequency.weekly),
        executeBackup: (_) async {
          attempts += 1;
          return const BackupResult(
            success: false,
            failureReason: BackupFailureReason.outputDirectoryUnavailable,
          );
        },
        onBackupCompleted: (_) async {},
        clock: () => DateTime(2026, 8, 4, 12),
      );
      addTearDown(scheduler.dispose);

      expect(await scheduler.checkNow(), isFalse);
      expect(await scheduler.checkNow(), isFalse);
      expect(attempts, 1);
    });
  });
}

AutoBackupSchedule _schedule({
  String directory = '/tmp/backups',
  BackupFrequency frequency = BackupFrequency.manual,
  List<int> weekdays = const <int>[DateTime.monday],
  int dayOfMonth = 1,
  int hour = 2,
  int minute = 0,
  DateTime? lastBackupTime,
}) {
  return AutoBackupSchedule(
    directory: directory,
    frequency: frequency,
    weekdays: weekdays,
    dayOfMonth: dayOfMonth,
    hour: hour,
    minute: minute,
    lastBackupTime: lastBackupTime,
  );
}
