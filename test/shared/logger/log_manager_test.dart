// 职责: 验证日志构造前的级别判断、动态级别过滤、文件输出与归档行为
// 关联文件:
//   lib/shared/logger/log_manager.dart
//   lib/shared/logger/compact_printer.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/directory-structure.md
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:reveric/shared/logger/app_logger.dart';
import 'package:reveric/shared/logger/compact_printer.dart';
import 'package:reveric/shared/logger/log_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('guarded logging', () {
    late Directory tempDir;
    final manager = LogManager.instance;
    final module = AppLogger.forModule('GuardTest');
    final events = <LogEvent>[];
    final outputs = <OutputEvent>[];
    void onLog(LogEvent event) => events.add(event);
    void onOutput(OutputEvent event) => outputs.add(event);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'reveric_guard_log_test_',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tempDir.path,
          );
      await manager.initialize(level: Level.info);
      expect(manager.isInitialized, isTrue);
      events.clear();
      outputs.clear();
      Logger.addLogListener(onLog);
      Logger.addOutputListener(onOutput);
    });

    tearDown(() async {
      Logger.removeLogListener(onLog);
      Logger.removeOutputListener(onOutput);
      await manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await tempDir.delete(recursive: true);
    });

    test('info threshold skips message evaluation and debug/trace events', () {
      String forbidden() => throw StateError('disabled builder executed');
      if (AppLogger.isDebugEnabled) {
        AppLogger.debug(forbidden());
      }
      if (AppLogger.isTraceEnabled) {
        AppLogger.trace(forbidden());
      }
      if (module.isDebugEnabled) {
        module.debug(forbidden());
      }
      if (module.isTraceEnabled) {
        module.trace(forbidden());
      }
      AppLogger.debug('static debug');
      AppLogger.trace('static trace');
      module.debug('module debug');
      module.trace('module trace');
      manager.debug('direct debug');
      manager.trace('direct trace');
      expect(events, isEmpty);
      expect(outputs, isEmpty);
    });

    test('enabled messages evaluate once and preserve module prefixes', () {
      AppLogger.setLogLevel(Level.trace);
      events.clear();
      outputs.clear();
      var calls = 0;
      String message() => 'message ${++calls}';
      if (AppLogger.isDebugEnabled) {
        AppLogger.debug(message());
      }
      if (AppLogger.isTraceEnabled) {
        AppLogger.trace(message());
      }
      if (module.isDebugEnabled) {
        module.debug(message());
      }
      if (module.isTraceEnabled) {
        module.trace(message());
      }
      expect(calls, 4);
      expect(events.map((event) => event.message), [
        'message 1',
        'message 2',
        '[GuardTest] message 3',
        '[GuardTest] message 4',
      ]);
      expect(outputs.map((event) => event.level), [
        Level.debug,
        Level.trace,
        Level.debug,
        Level.trace,
      ]);
    });

    test('runtime thresholds use the same predicate as output filtering', () {
      for (final threshold in [
        Level.trace,
        Level.debug,
        Level.info,
        Level.off,
      ]) {
        AppLogger.setLogLevel(threshold);
        outputs.clear();
        var builds = 0;
        String message() {
          builds++;
          return 'dynamic';
        }

        if (module.isTraceEnabled) {
          module.trace(message());
        }
        if (module.isDebugEnabled) {
          module.debug(message());
        }
        module.info('info');
        module.warning('warning');
        module.error('error');
        final levels = [
          Level.trace,
          Level.debug,
          Level.info,
          Level.warning,
          Level.error,
        ];
        expect(
          outputs.map((event) => event.level),
          levels.where(module.isEnabled),
        );
        expect(
          builds,
          [Level.trace, Level.debug].where(module.isEnabled).length,
        );
      }
    });

    test(
      'switching levels keeps file output alive and flushes on dispose',
      () async {
        AppLogger.setLogLevel(Level.debug);
        if (module.isDebugEnabled) {
          module.debug('first enabled marker');
        }
        AppLogger.setLogLevel(Level.info);
        module.debug('disabled marker');
        AppLogger.setLogLevel(Level.trace);
        if (module.isTraceEnabled) {
          module.trace('second enabled marker');
        }
        final path = manager.logFilePath!;
        await manager.dispose();
        final content = await File(path).readAsString();
        expect(content, contains('[DEBUG] [GuardTest] first enabled marker'));
        expect(content, contains('[TRACE] [GuardTest] second enabled marker'));
        expect(content, isNot(contains('disabled marker')));
        expect('=== Reveric Startup Log ==='.allMatches(content), hasLength(1));
      },
    );
  });

  group('CompactLogPrinter', () {
    test('writes normal events on one line with time, level and module', () {
      final time = DateTime.utc(2026, 9, 24, 12, 34, 56);
      final lines = CompactLogPrinter().log(
        LogEvent(Level.info, '[Agent] request completed', time: time),
      );

      expect(lines, [
        '2026-09-24T12:34:56.000Z [INFO] [Agent] request completed',
      ]);
    });

    test('preserves multiline errors and every supplied stack frame', () {
      const message = '[Agent] request failed\nprovider response detail';
      final error = StateError('upstream failed\nresponse body');
      final stack = List.generate(
        12,
        (index) => '#$index caller$index (package:example/app.dart:$index:1)',
      ).join('\n');
      final lines = CompactLogPrinter().log(
        LogEvent(
          Level.error,
          message,
          error: error,
          stackTrace: StackTrace.fromString(stack),
        ),
      );

      expect(lines.first, endsWith('[ERROR] $message'));
      expect(lines[1], 'Error: $error');
      expect(lines[2], stack);
    });
  });

  group('LogManager.prepareLatestLogFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reveric_log_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('keeps latest.log when it is at or below the size limit', () async {
      final latestLog = File(p.join(tempDir.path, 'latest.log'));
      await latestLog.writeAsBytes(List.filled(16, 65));

      await LogManager.prepareLatestLogFile(
        tempDir.path,
        maxLatestLogSizeBytes: 16,
      );

      expect(latestLog.existsSync(), isTrue);
      expect(await latestLog.length(), 16);
      expect(await _startupLogFiles(tempDir), isEmpty);
    });

    test('archives latest.log only after it exceeds the size limit', () async {
      final latestLog = File(p.join(tempDir.path, 'latest.log'));
      await latestLog.writeAsBytes(List.filled(17, 65));

      await LogManager.prepareLatestLogFile(
        tempDir.path,
        maxLatestLogSizeBytes: 16,
      );

      expect(latestLog.existsSync(), isTrue);
      expect(await latestLog.length(), 0);

      final startupLogs = await _startupLogFiles(tempDir);
      expect(startupLogs, hasLength(1));
      expect(await startupLogs.single.length(), 17);
    });

    test('appendCheckpointSync persists a checkpoint immediately', () {
      final file = File(p.join(tempDir.path, 'latest.log'));

      LogManager.appendCheckpointSync(
        file.path,
        'native call started',
        timestamp: DateTime.utc(2026, 8, 6, 12),
      );

      final content = file.readAsStringSync();
      expect(content, contains('2026-08-06T12:00:00.000Z'));
      expect(content, contains('[Checkpoint] native call started'));
    });
  });
}

Future<List<File>> _startupLogFiles(Directory directory) async {
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).startsWith('startup_'))
      .toList();
}
