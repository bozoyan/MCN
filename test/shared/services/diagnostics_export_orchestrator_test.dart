// 职责: 验证诊断包包含反馈上下文、当前日志与最近一份崩溃转储。
// 关联文件:
//   lib/shared/services/diagnostics_export_orchestrator.dart
//   lib/shared/services/crash_reporting/native_crash_reporting.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/diagnostics_export_orchestrator.dart';

void main() {
  late Directory directory;
  late File log;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('diagnostics_export_');
    Directory('${directory.path}/logs').createSync();
    log = File('${directory.path}/logs/latest.log')
      ..writeAsStringSync('diagnostic log 日志');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<Map<String, List<int>>> bundle(String? logPath) async {
    final bytes = await DiagnosticsExportOrchestrator().buildBundle(
      feedback: {'description': '回复中断', 'message_count': 2},
      logPath: logPath,
    );
    return {
      for (final file in ZipDecoder().decodeBytes(bytes).files)
        file.name: file.content,
    };
  }

  test('bundles feedback and the current log without a crash dump', () async {
    final files = await bundle(log.path);

    expect(files.keys, unorderedEquals(['feedback.json', 'latest.log']));
    expect(jsonDecode(utf8.decode(files['feedback.json']!)), {
      'description': '回复中断',
      'message_count': 2,
    });
    expect(utf8.decode(files['latest.log']!), 'diagnostic log 日志');
  });

  test('includes the newest non-empty crash dump', () async {
    final crashes = Directory('${directory.path}/crashes')..createSync();
    File('${crashes.path}/crash_old.dmp')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(DateTime(2026, 1, 1));
    File('${crashes.path}/crash_new.dmp')
      ..writeAsBytesSync([2, 3])
      ..setLastModifiedSync(DateTime(2026, 1, 2));
    File('${crashes.path}/crash_empty.dmp').writeAsBytesSync([]);

    final files = await bundle(log.path);

    expect(files['latest.dump'], [2, 3]);
    expect(files.containsKey('latest.log'), isTrue);
  });

  test('still bundles feedback when no log is available', () async {
    final files = await bundle(null);

    expect(files.keys, ['feedback.json']);
  });
}
