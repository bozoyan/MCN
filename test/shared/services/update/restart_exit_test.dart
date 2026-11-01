// 职责: 验证更新清理失败或挂起时仍会上报并终止当前进程，正常退出先完成清理。
// 关联文件:
//   lib/shared/services/update/restart_exit.dart
//   lib/shared/logger/startup_failure_reporter.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';
import 'package:reveric/shared/services/update/restart_exit.dart';

void main() {
  test(
    'normal exit marks clean before releasing lock and terminating',
    () async {
      final calls = <String>[];
      await exitForUpdate(
        releaseInstance: () async {
          calls.add('unlock');
        },
        markCleanExit: () => calls.add('clean'),
        terminate: (code) => calls.add('exit:$code'),
        failureReporter: _Reporter(calls),
      );
      expect(calls, ['clean', 'unlock', 'exit:0']);
    },
  );

  for (final hangs in [false, true]) {
    test(
      'cleanup ${hangs ? 'timeout' : 'failure'} reports before exit',
      () async {
        final calls = <String>[];
        await exitForUpdate(
          releaseInstance: () => hangs
              ? Completer<void>().future
              : Future.error(StateError('locked')),
          markCleanExit: () => calls.add('clean'),
          terminate: (code) => calls.add('exit:$code'),
          failureReporter: _Reporter(calls),
          cleanupTimeout: const Duration(milliseconds: 20),
        );
        expect(calls, [
          'clean',
          'report:update_exit:release_instance_${hangs ? 'timeout' : 'failed'}',
          'exit:0',
        ]);
      },
    );
  }

  test('a reporting exception cannot strand the exiting process', () async {
    final calls = <String>[];
    await exitForUpdate(
      releaseInstance: () => Future.error(StateError('cleanup')),
      markCleanExit: () => calls.add('clean'),
      terminate: (code) => calls.add('exit:$code'),
      failureReporter: _Reporter(calls, fail: true),
    );
    expect(calls.last, 'exit:0');
    expect(calls.first, 'clean');
  });

  test('a stalled report still allows the process to exit', () async {
    final calls = <String>[];
    await exitForUpdate(
      releaseInstance: () => Future.error(StateError('cleanup')),
      markCleanExit: () {},
      terminate: (code) => calls.add('exit:$code'),
      failureReporter: _Reporter(calls, hang: true),
    ).timeout(const Duration(seconds: 6));
    expect(calls.last, 'exit:0');
  });
}

class _Reporter extends StartupFailureReporter {
  _Reporter(this.calls, {this.fail = false, this.hang = false});
  final List<String> calls;
  final bool fail;
  final bool hang;

  @override
  Future<void> reportLifecycleFailure({
    required String phase,
    required String reason,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    calls.add('report:$phase:$reason');
    if (fail) {
      throw StateError('report unavailable');
    }
    if (hang) {
      await Completer<void>().future;
    }
  }
}
