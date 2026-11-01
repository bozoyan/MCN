// 职责: 自动备份调度 — 按日、周或月计划在应用运行及恢复前台时触发备份。
// 关联文件:
//   lib/shared/services/backup_service.dart
//   lib/shared/providers/settings_providers.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/service-naming.md

import 'dart:async';

import '../logger/app_logger.dart';
import 'backup_service.dart';

enum BackupFrequency { manual, daily, weekly, monthly }

class AutoBackupSchedule {
  const AutoBackupSchedule({
    required this.directory,
    required this.frequency,
    required this.weekdays,
    required this.dayOfMonth,
    required this.hour,
    required this.minute,
    required this.lastBackupTime,
  });

  final String directory;
  final BackupFrequency frequency;
  final List<int> weekdays;
  final int dayOfMonth;
  final int hour;
  final int minute;
  final DateTime? lastBackupTime;

  bool get enabled =>
      directory.trim().isNotEmpty &&
      frequency != BackupFrequency.manual &&
      (frequency != BackupFrequency.weekly || weekdays.isNotEmpty);

  AutoBackupSchedule normalized() {
    return AutoBackupSchedule(
      directory: directory.trim(),
      frequency: frequency,
      weekdays: _normalizeWeekdays(weekdays),
      dayOfMonth: dayOfMonth.clamp(1, 28),
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      lastBackupTime: lastBackupTime,
    );
  }

  bool hasSamePlan(AutoBackupSchedule other) {
    return directory == other.directory &&
        frequency == other.frequency &&
        _sameWeekdays(weekdays, other.weekdays) &&
        dayOfMonth == other.dayOfMonth &&
        hour == other.hour &&
        minute == other.minute;
  }
}

typedef AutoBackupExecutor =
    Future<BackupResult> Function(String outputDirectory);
typedef AutoBackupCompletion = Future<void> Function(DateTime completedAt);
typedef AutoBackupTimerFactory =
    Timer Function(Duration delay, void Function() callback);

final _log = AppLogger.forModule('AutoBackup');

class AutoBackupScheduler {
  AutoBackupScheduler({
    required AutoBackupSchedule schedule,
    required this._executeBackup,
    required this._onBackupCompleted,
    DateTime Function()? clock,
    AutoBackupTimerFactory? timerFactory,
  }) : _schedule = schedule.normalized(),
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final AutoBackupExecutor _executeBackup;
  final AutoBackupCompletion _onBackupCompleted;
  final DateTime Function() _clock;
  final AutoBackupTimerFactory _timerFactory;

  AutoBackupSchedule _schedule;
  Timer? _timer;
  DateTime? _lastAttemptedOccurrence;
  bool _started = false;
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;

  void start() {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    _log.info('scheduler started');
    unawaited(checkNow());
  }

  void updateSchedule(AutoBackupSchedule schedule) {
    if (_disposed) {
      return;
    }
    final normalized = schedule.normalized();
    if (!_schedule.hasSamePlan(normalized)) {
      _lastAttemptedOccurrence = null;
    }
    _schedule = normalized;
    if (_started) {
      unawaited(checkNow());
    }
  }

  Future<bool> checkNow() async {
    if (_disposed || _running) {
      return false;
    }

    _timer?.cancel();
    _timer = null;
    final schedule = _schedule;
    if (!schedule.enabled) {
      _log.debug('scheduler disabled');
      return false;
    }

    final now = _clock();
    final occurrence = latestBackupOccurrenceAtOrBefore(now, schedule);
    final lastBackupTime = schedule.lastBackupTime;
    final due =
        occurrence != null &&
        (lastBackupTime == null || lastBackupTime.isBefore(occurrence));
    if (!due || _lastAttemptedOccurrence == occurrence) {
      _scheduleNextCheck(now);
      return false;
    }

    _running = true;
    _lastAttemptedOccurrence = occurrence;
    _log.info(
      'automatic backup started, occurrence=$occurrence, '
      'frequency=${schedule.frequency.name}',
    );
    try {
      final result = await _executeBackup(schedule.directory);
      if (!result.success) {
        _log.warning(
          'automatic backup failed, occurrence=$occurrence, '
          'reason=${result.failureReason}',
        );
        return false;
      }

      final completedAt = _clock();
      await _onBackupCompleted(completedAt);
      _log.info(
        'automatic backup completed, occurrence=$occurrence, '
        'completedAt=$completedAt',
      );
      return true;
    } catch (error, stackTrace) {
      _log.error(
        'automatic backup threw, occurrence=$occurrence',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _running = false;
      _scheduleNextCheck(_clock());
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNextCheck(DateTime now) {
    if (!_started || _disposed || !_schedule.enabled) {
      return;
    }
    _timer?.cancel();
    final next = nextBackupOccurrenceAfter(now, _schedule);
    if (next == null) {
      return;
    }
    final delay = next.difference(now);
    if (_log.isDebugEnabled) {
      _log.debug('next automatic backup scheduled at $next');
    }
    _timer = _timerFactory(delay, () {
      unawaited(checkNow());
    });
  }
}

DateTime? latestBackupOccurrenceAtOrBefore(
  DateTime now,
  AutoBackupSchedule schedule,
) {
  final normalized = schedule.normalized();
  return switch (normalized.frequency) {
    BackupFrequency.manual => null,
    BackupFrequency.daily => _dailyOccurrenceAtOrBefore(now, normalized),
    BackupFrequency.weekly => _weeklyOccurrenceAtOrBefore(now, normalized),
    BackupFrequency.monthly => _monthlyOccurrenceAtOrBefore(now, normalized),
  };
}

DateTime? nextBackupOccurrenceAfter(DateTime now, AutoBackupSchedule schedule) {
  final normalized = schedule.normalized();
  return switch (normalized.frequency) {
    BackupFrequency.manual => null,
    BackupFrequency.daily => _nextDailyOccurrence(now, normalized),
    BackupFrequency.weekly => _nextWeeklyOccurrence(now, normalized),
    BackupFrequency.monthly => _nextMonthlyOccurrence(now, normalized),
  };
}

DateTime _dailyOccurrenceAtOrBefore(DateTime now, AutoBackupSchedule schedule) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    schedule.hour,
    schedule.minute,
  );
  if (!today.isAfter(now)) {
    return today;
  }
  return DateTime(
    now.year,
    now.month,
    now.day - 1,
    schedule.hour,
    schedule.minute,
  );
}

DateTime? _weeklyOccurrenceAtOrBefore(
  DateTime now,
  AutoBackupSchedule schedule,
) {
  DateTime? latest;
  for (final weekday in schedule.weekdays) {
    final daysSinceScheduledWeekday =
        (now.weekday - weekday + DateTime.daysPerWeek) % DateTime.daysPerWeek;
    var occurrence = DateTime(
      now.year,
      now.month,
      now.day - daysSinceScheduledWeekday,
      schedule.hour,
      schedule.minute,
    );
    if (occurrence.isAfter(now)) {
      occurrence = DateTime(
        occurrence.year,
        occurrence.month,
        occurrence.day - DateTime.daysPerWeek,
        schedule.hour,
        schedule.minute,
      );
    }
    if (latest == null || occurrence.isAfter(latest)) {
      latest = occurrence;
    }
  }
  return latest;
}

DateTime _monthlyOccurrenceAtOrBefore(
  DateTime now,
  AutoBackupSchedule schedule,
) {
  final thisMonth = DateTime(
    now.year,
    now.month,
    schedule.dayOfMonth,
    schedule.hour,
    schedule.minute,
  );
  if (!thisMonth.isAfter(now)) {
    return thisMonth;
  }
  return DateTime(
    now.year,
    now.month - 1,
    schedule.dayOfMonth,
    schedule.hour,
    schedule.minute,
  );
}

DateTime _nextDailyOccurrence(DateTime now, AutoBackupSchedule schedule) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    schedule.hour,
    schedule.minute,
  );
  if (today.isAfter(now)) {
    return today;
  }
  return DateTime(
    now.year,
    now.month,
    now.day + 1,
    schedule.hour,
    schedule.minute,
  );
}

DateTime? _nextWeeklyOccurrence(DateTime now, AutoBackupSchedule schedule) {
  DateTime? next;
  for (final weekday in schedule.weekdays) {
    final daysUntilScheduledWeekday =
        (weekday - now.weekday + DateTime.daysPerWeek) % DateTime.daysPerWeek;
    var occurrence = DateTime(
      now.year,
      now.month,
      now.day + daysUntilScheduledWeekday,
      schedule.hour,
      schedule.minute,
    );
    if (!occurrence.isAfter(now)) {
      occurrence = DateTime(
        occurrence.year,
        occurrence.month,
        occurrence.day + DateTime.daysPerWeek,
        schedule.hour,
        schedule.minute,
      );
    }
    if (next == null || occurrence.isBefore(next)) {
      next = occurrence;
    }
  }
  return next;
}

DateTime _nextMonthlyOccurrence(DateTime now, AutoBackupSchedule schedule) {
  final thisMonth = DateTime(
    now.year,
    now.month,
    schedule.dayOfMonth,
    schedule.hour,
    schedule.minute,
  );
  if (thisMonth.isAfter(now)) {
    return thisMonth;
  }
  return DateTime(
    now.year,
    now.month + 1,
    schedule.dayOfMonth,
    schedule.hour,
    schedule.minute,
  );
}

List<int> _normalizeWeekdays(Iterable<int> weekdays) {
  final normalized =
      weekdays
          .where(
            (weekday) =>
                weekday >= DateTime.monday && weekday <= DateTime.sunday,
          )
          .toSet()
          .toList()
        ..sort();
  return List<int>.unmodifiable(normalized);
}

bool _sameWeekdays(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
