// 职责: 验证最近崩溃转储整理、原生摘要解析、扫描与上报标记。
// 关联文件:
//   lib/shared/services/crash_reporting/native_crash_reporting.dart
//   lib/shared/logger/startup_failure_reporter.dart

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';
import 'package:reveric/shared/services/crash_reporting/native_crash_reporting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('native_crash_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('latest dump', () {
    test('absent crash directory has no dump', () async {
      expect(
        await NativeCrashReporting.prepareLatestDump('${tempDir.path}/missing'),
        isNull,
      );
    });

    test('copies newest nonempty dump and preserves originals', () async {
      final old = File('${tempDir.path}/crash_old.dmp')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(DateTime(2026, 1));
      final newer = File('${tempDir.path}/crash_new.dmp')
        ..writeAsBytesSync([2, 3])
        ..setLastModifiedSync(DateTime(2026, 2));
      File('${tempDir.path}/crash_empty.dmp').writeAsBytesSync([]);
      File('${tempDir.path}/unrelated.dmp').writeAsBytesSync([4]);
      final latest = await NativeCrashReporting.prepareLatestDump(tempDir.path);
      expect(latest!.path, '${tempDir.path}/latest.dump');
      expect(await latest.readAsBytes(), [2, 3]);
      expect(await latest.lastModified(), await newer.lastModified());
      expect(await old.readAsBytes(), [1]);
      expect(await newer.readAsBytes(), [2, 3]);
      await NativeCrashReporting.prepareLatestDump(tempDir.path);
      expect(await latest.readAsBytes(), [2, 3]);
      newer
        ..writeAsBytesSync([5])
        ..setLastModifiedSync(DateTime(2026, 3));
      await NativeCrashReporting.prepareLatestDump(tempDir.path);
      expect(await latest.readAsBytes(), [5]);
      expect(tempDir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('keeps a newer existing latest.dump', () async {
      File('${tempDir.path}/crash_old.dmp')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(DateTime(2026, 1));
      final latest = File('${tempDir.path}/latest.dump')
        ..writeAsBytesSync([2])
        ..setLastModifiedSync(DateTime(2026, 2));
      await NativeCrashReporting.prepareLatestDump(tempDir.path);
      expect(await latest.readAsBytes(), [2]);
    });

    test('empty dumps do not become upload attachments', () async {
      File('${tempDir.path}/crash_empty.dmp').writeAsBytesSync([]);
      File('${tempDir.path}/latest.dump').writeAsBytesSync([]);
      expect(
        await NativeCrashReporting.prepareLatestDump(tempDir.path),
        isNull,
      );
    });

    test(
      'failed replacement preserves source and removes staging file',
      () async {
        final source = File('${tempDir.path}/crash_new.dmp')
          ..writeAsBytesSync([1, 2]);
        Directory('${tempDir.path}/latest.dump').createSync();
        await expectLater(
          NativeCrashReporting.prepareLatestDump(tempDir.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await source.readAsBytes(), [1, 2]);
        expect(
          tempDir.listSync().where((f) => f.path.endsWith('.tmp')),
          isEmpty,
        );
      },
    );

    test(
      'startup prepares dump even when summary was already reported',
      () async {
        File('${tempDir.path}/crash_old.dmp').writeAsBytesSync([1, 2]);
        final reporting = NativeCrashReporting(
          reportSink:
              ({required phase, required error, required stackTrace}) async {
                fail('No pending summary should be uploaded');
              },
        );
        await reporting.reportPendingCrashes(tempDir.path);
        expect(await File('${tempDir.path}/latest.dump').readAsBytes(), [1, 2]);
      },
    );
  });

  File writeSummary(
    String name, {
    String kind = 'unhandled_exception',
    String timestamp = '2026-08-06T12:00:00 (local)',
    String pid = '1234',
    String exceptionCode = '0xC0000005',
    String exceptionAddress = '0x00007FFB12345678',
    String module = r'C:\app\flutter_windows.dll',
    String dumpFile = r'C:\app\crashes\crash.dmp',
  }) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(
      'kind: $kind\n'
      'timestamp: $timestamp\n'
      'pid: $pid\n'
      'exception_code: $exceptionCode\n'
      'exception_address: $exceptionAddress\n'
      'module: $module\n'
      'dump_file: $dumpFile\n',
    );
    return file;
  }

  test('tryParseSummary parses a native crash summary', () {
    final file = writeSummary('crash_20260806_120000_pid1234.txt');

    final summary = NativeCrashReporting.tryParseSummary(file);

    expect(summary, isNotNull);
    expect(summary!.kind, 'unhandled_exception');
    expect(summary.occurredAt, '2026-08-06T12:00:00 (local)');
    expect(summary.pid, '1234');
    expect(summary.exceptionCode, '0xC0000005');
    expect(summary.exceptionAddress, '0x00007FFB12345678');
    expect(summary.module, r'C:\app\flutter_windows.dll');
    expect(summary.dumpPath, r'C:\app\crashes\crash.dmp');
  });

  test(
    'configure passes the marker session token to the native handler',
    () async {
      const channel = MethodChannel('reveric/crash_reporting');
      final marker = File('${tempDir.path}/session_running.marker')
        ..writeAsStringSync(jsonEncode({'session_token': '123456-42'}));
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return {'crashDumpDir': tempDir.path};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(
        await NativeCrashReporting().configure(sessionMarkerPath: marker.path),
        tempDir.path,
      );
      expect(received!.arguments['sessionToken'], '123456-42');
      expect(received!.arguments['sessionMarkerPath'], marker.path);
    },
  );

  test('unreadable summary has an explicit read failure reason', () {
    final failures = <String>[];
    final summary = NativeCrashReporting.tryParseSummary(
      File('${tempDir.path}/missing.txt'),
      onFailure: failures.add,
    );
    expect(summary, isNull);
    expect(failures, ['read_failed']);
  });

  test('tryParseSummary returns null for malformed content', () {
    final file = File('${tempDir.path}/crash_bad.txt')
      ..writeAsStringSync('garbage without expected fields\n');

    expect(NativeCrashReporting.tryParseSummary(file), isNull);
  });

  test(
    'UTF-8 BOM and dump failure remain diagnosable without uploading paths',
    () {
      final file = writeSummary('crash_bom.txt');
      file.writeAsStringSync('\uFEFF${file.readAsStringSync()}dump_error: 5\n');
      final summary = NativeCrashReporting.tryParseSummary(file)!;
      expect(summary.kind, 'unhandled_exception');
      expect(summary.dumpError, '5');
      final report = NativeCrashReport(summary).toString();
      expect(report, contains('classification=confirmed_crash'));
      expect(report, contains('dump_error=5'));
      expect(report, contains('module=flutter_windows.dll'));
      expect(report, isNot(contains(r'C:\app')));
    },
  );

  test(
    'malformed summary is reported as diagnostic failure, not crash proof',
    () async {
      final file = File('${tempDir.path}/crash_bad.txt')
        ..writeAsStringSync('private garbage');
      final reports = <String>[];
      final reporting = NativeCrashReporting(
        reportSink:
            ({required phase, required error, required stackTrace}) async {
              reports.add('$phase|$error');
              return StartupFailureReportOutcome.reported;
            },
      );
      await reporting.reportPendingCrashes(tempDir.path);
      expect(reports.single, startsWith('native_crash_summary_parse_failed|'));
      expect(reports.single, isNot(contains('private garbage')));
      expect(reports.single, isNot(contains('confirmed_crash')));
      expect(file.existsSync(), isFalse);
      expect(
        File('${tempDir.path}/crash_bad.reported.txt').existsSync(),
        isTrue,
      );
      await reporting.reportPendingCrashes(tempDir.path);
      expect(reports, hasLength(1));
    },
  );

  test(
    'scanPending skips reported and non-summary files, sorted by name',
    () async {
      writeSummary('crash_20260806_120200_pid2.txt', pid: '2');
      writeSummary('crash_20260806_120000_pid1.txt', pid: '1');
      writeSummary('crash_20260805_235900_pid0.reported.txt', pid: '0');
      File(
        '${tempDir.path}/crash_20260806_120100_pid9.dmp',
      ).writeAsStringSync('binary');
      File('${tempDir.path}/unrelated.txt').writeAsStringSync('x');

      final reporting = NativeCrashReporting(
        reportSink:
            ({required phase, required error, required stackTrace}) async {
              return StartupFailureReportOutcome.reported;
            },
      );
      final pending = reporting.scanPending(tempDir.path);

      expect(pending, hasLength(2));
      expect(pending[0].pid, '1');
      expect(pending[1].pid, '2');
    },
  );

  test(
    'reportPendingCrashes reports and renames summaries to .reported.txt',
    () async {
      writeSummary('crash_20260806_120000_pid1.txt');
      final reports = <String>[];
      final reporting = NativeCrashReporting(
        reportSink:
            ({required phase, required error, required stackTrace}) async {
              reports.add('$phase|$error');
              return StartupFailureReportOutcome.reported;
            },
      );

      await reporting.reportPendingCrashes(tempDir.path);

      expect(reports, hasLength(1));
      expect(reports.single, startsWith('native_crash|'));
      expect(reports.single, contains('0xC0000005'));
      expect(reports.single, contains('flutter_windows.dll'));

      // 已上报文件被改名，再次扫描为空。
      expect(reporting.scanPending(tempDir.path), isEmpty);
      expect(
        File(
          '${tempDir.path}/crash_20260806_120000_pid1.reported.txt',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'reportPendingCrashes caps reports per launch and marks stale ones',
    () async {
      for (var i = 0; i < NativeCrashReporting.maxReportsPerLaunch + 2; i++) {
        writeSummary(
          'crash_20260806_1200${i.toString().padLeft(2, '0')}_pid$i.txt',
          pid: '$i',
        );
      }
      final reports = <String>[];
      final reporting = NativeCrashReporting(
        reportSink:
            ({required phase, required error, required stackTrace}) async {
              reports.add('$phase|$error');
              return StartupFailureReportOutcome.reported;
            },
      );

      await reporting.reportPendingCrashes(tempDir.path);

      // 只上报最新的 maxReportsPerLaunch 条，更早的标记为已上报但不发送。
      expect(reports, hasLength(NativeCrashReporting.maxReportsPerLaunch));
      expect(reports.first, contains('pid=2'));
      expect(reporting.scanPending(tempDir.path), isEmpty);
    },
  );

  test('keeps the summary pending when upload is retryable', () async {
    writeSummary('crash_20260806_120000_pid1.txt');
    final reporting = NativeCrashReporting(
      reportSink:
          ({required phase, required error, required stackTrace}) async {
            return StartupFailureReportOutcome.retryableFailure;
          },
    );

    await reporting.reportPendingCrashes(tempDir.path);

    expect(reporting.scanPending(tempDir.path), hasLength(1));
    expect(
      File('${tempDir.path}/crash_20260806_120000_pid1.txt').existsSync(),
      isTrue,
    );
  });
}
