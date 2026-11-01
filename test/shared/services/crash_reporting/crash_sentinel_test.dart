// 职责: 验证崩溃哨兵的 marker 写入、上次异常终止识别与正常退出清除。
// 关联文件:
//   lib/shared/services/crash_reporting/crash_sentinel.dart
//   lib/shared/logger/startup_failure_reporter.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';
import 'package:reveric/shared/services/crash_reporting/crash_sentinel.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crash_sentinel_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  CrashSentinel buildSentinel({
    List<String>? reports,
    StartupFailureReportOutcome reportOutcome =
        StartupFailureReportOutcome.reported,
  }) {
    return CrashSentinel(
      logDirectory: tempDir.path,
      reportSink:
          ({required phase, required error, required stackTrace}) async {
            reports?.add('$phase|$error');
            return reportOutcome;
          },
      now: () => DateTime.utc(2026, 8, 6, 12),
      currentPid: () => 4321,
    );
  }

  test('returns null when no marker exists (clean first run)', () async {
    final sentinel = buildSentinel();
    expect(await sentinel.checkPreviousSession(), isNull);
  });

  test(
    'marker written by previous session is detected as abnormal termination',
    () async {
      final firstRun = buildSentinel();
      await firstRun.markSessionStart();

      final markerFile = File(firstRun.markerPath);
      expect(markerFile.existsSync(), isTrue);
      final payload =
          jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
      expect(payload['pid'], 4321);
      expect(payload['started_at'], '2026-08-06T12:00:00.000Z');
      expect(payload['app_version'], isNotEmpty);
      expect(payload['marker_schema_version'], 3);
      expect(payload['native_handler_configured'], isFalse);

      // 第二次启动（marker 残留 = 上次未正常退出）。
      final secondRun = buildSentinel();
      final crash = await secondRun.checkPreviousSession();
      expect(crash, isNotNull);
      expect(crash!.markerContent, contains('"pid":4321'));
    },
  );

  test('native handler readiness is persisted in the active marker', () async {
    final sentinel = buildSentinel();
    await sentinel.markSessionStart();

    expect(await sentinel.markNativeHandlerConfigured(), isTrue);

    final payload =
        jsonDecode(File(sentinel.markerPath).readAsStringSync())
            as Map<String, dynamic>;
    expect(payload['pid'], 4321);
    expect(payload['started_at'], '2026-08-06T12:00:00.000Z');
    expect(payload['native_handler_configured'], isTrue);
    expect(payload['native_handler_configured_at'], '2026-08-06T12:00:00.000Z');
  });

  test(
    'previous marker is preserved before current session overwrites it',
    () async {
      final reports = <String>[];
      final firstRun = buildSentinel(reports: reports);
      await firstRun.markSessionStart();

      final secondRun = buildSentinel(reports: reports);
      expect(await secondRun.preservePreviousSessionCrash(), isTrue);
      await secondRun.markSessionStart();
      expect(reports, isEmpty);

      expect(await secondRun.reportPendingSessionCrashes(), isTrue);
      expect(reports, hasLength(1));
      expect(reports.single, contains('origin=pending_replay'));
      expect(reports.single, contains('"native_handler_configured":false'));
      expect(reports.single, contains('"preserved_from":"current_marker"'));

      final activePayload =
          jsonDecode(File(secondRun.markerPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(activePayload['pid'], 4321);
      expect(File(secondRun.markerPath).existsSync(), isTrue);
      expect(
        Directory(secondRun.pendingCrashDirectoryPath).listSync(),
        isEmpty,
      );
    },
  );

  test('clean exit deletes the marker so next start reports nothing', () async {
    final firstRun = buildSentinel();
    await firstRun.markSessionStart();
    await firstRun.markCleanExit();

    final secondRun = buildSentinel();
    expect(await secondRun.checkPreviousSession(), isNull);
  });

  test('unknown termination and interrupted cleanup are distinct', () async {
    final sentinel = buildSentinel();
    await sentinel.markSessionStart();
    expect(
      (await sentinel.checkPreviousSession())!.classification,
      'unknown_termination',
    );
    sentinel.markExitProgressSync(
      source: 'tray',
      phase: 'closing_app_database',
    );
    final marker =
        jsonDecode(File(sentinel.markerPath).readAsStringSync()) as Map;
    File('${sentinel.markerPath}.native').writeAsStringSync(
      jsonEncode({
        'pid': marker['pid'],
        'session_token': marker['session_token'],
        'native_exit_source': 'none',
        'native_exit_phase': 'running',
        'native_crash': false,
      }),
    );
    final crash = (await sentinel.checkPreviousSession())!;
    expect(crash.classification, 'exit_incomplete');
    expect(crash.toString(), contains('closing_app_database'));
    await sentinel.markCleanExit();
    expect(await sentinel.checkPreviousSession(), isNull);
  });

  test(
    'native evidence must match the session and survives pending replay',
    () async {
      final sentinel = buildSentinel();
      await sentinel.markSessionStart();
      final marker =
          jsonDecode(File(sentinel.markerPath).readAsStringSync()) as Map;
      final native = File('${sentinel.markerPath}.native');
      final evidence = {
        'pid': marker['pid'],
        'session_token': 'old-session',
        'native_crash': true,
        'native_exit_phase': 'crash_handler',
        'dump_status': 'failed',
        'dump_error': 5,
        'summary_error': 13,
      };
      native.writeAsStringSync(jsonEncode(evidence));
      expect(
        (await sentinel.checkPreviousSession())!.classification,
        'unknown_termination',
      );
      evidence['session_token'] = marker['session_token'];
      native.writeAsStringSync(jsonEncode(evidence));
      final crash = (await sentinel.checkPreviousSession())!;
      expect(crash.classification, 'confirmed_crash');
      expect(crash.toString(), contains('"dump_error":5'));
      final reports = <String>[];
      final next = buildSentinel(reports: reports);
      expect(await next.preservePreviousSessionCrash(), isTrue);
      await next.markSessionStart();
      await next.reportPendingSessionCrashes();
      expect(reports.single, contains('classification=confirmed_crash'));
      expect(reports.single, contains('"summary_error":13'));
    },
  );

  test('unreadable marker content is still treated as a crash', () async {
    File(
      '${tempDir.path}/${CrashSentinel.markerFileName}',
    ).writeAsStringSync('### not json ###');

    final sentinel = buildSentinel();
    final crash = await sentinel.checkPreviousSession();
    expect(crash, isNotNull);
    expect(crash!.markerContent, contains('not json'));
  });

  test(
    'reportPreviousSessionCrash reports once and keeps the marker for overwrite',
    () async {
      final reports = <String>[];
      final firstRun = buildSentinel(reports: reports);
      await firstRun.markSessionStart();

      final secondRun = buildSentinel(reports: reports);
      await secondRun.reportPreviousSessionCrash();

      expect(reports, hasLength(1));
      expect(reports.single, startsWith('previous_session_crashed|'));
      expect(reports.single, contains('"pid":4321'));
      // 不删除 —— 由本次会话的 markSessionStart 覆盖。
      expect(File(secondRun.markerPath).existsSync(), isTrue);

      // 本次会话写入 marker 后正常退出，第三次启动不再上报。
      await secondRun.markSessionStart();
      await secondRun.markCleanExit();
      final thirdRun = buildSentinel(reports: reports);
      await thirdRun.reportPreviousSessionCrash();
      expect(reports, hasLength(1));
    },
  );

  test('markCleanExit tolerates a missing marker', () async {
    final sentinel = buildSentinel();
    await sentinel.markCleanExit();
    expect(File(sentinel.markerPath).existsSync(), isFalse);
  });

  test(
    'retryable report failure moves evidence to pending marker storage',
    () async {
      final firstRun = buildSentinel();
      await firstRun.markSessionStart();

      final secondRun = buildSentinel(
        reportOutcome: StartupFailureReportOutcome.retryableFailure,
      );
      final reported = await secondRun.reportPreviousSessionCrash();

      expect(reported, isFalse);
      expect(File(secondRun.markerPath).existsSync(), isTrue);
      final pendingDirectory = Directory(secondRun.pendingCrashDirectoryPath);
      expect(pendingDirectory.existsSync(), isTrue);
      expect(pendingDirectory.listSync(), hasLength(1));
      expect(
        File(secondRun.markerPath).readAsStringSync(),
        contains('"pid":4321'),
      );

      // 当前会话正常退出只删除 current marker，不会删除待重试证据。
      await secondRun.markSessionStart();
      secondRun.markCleanExitSync();
      expect(File(secondRun.markerPath).existsSync(), isFalse);
      expect(pendingDirectory.listSync(), hasLength(1));
    },
  );

  test('pending marker is removed after a later successful report', () async {
    final firstRun = buildSentinel(
      reportOutcome: StartupFailureReportOutcome.retryableFailure,
    );
    await firstRun.markSessionStart();
    expect(await firstRun.reportPreviousSessionCrash(), isFalse);
    firstRun.markCleanExitSync();

    final secondRun = buildSentinel();
    expect(await secondRun.reportPreviousSessionCrash(), isTrue);
    expect(Directory(secondRun.pendingCrashDirectoryPath).listSync(), isEmpty);
  });

  test('markCleanExitSync deletes the marker before process exit', () async {
    final sentinel = buildSentinel();
    await sentinel.markSessionStart();

    sentinel.markCleanExitSync();

    expect(File(sentinel.markerPath).existsSync(), isFalse);
  });
}
