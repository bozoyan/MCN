// 职责: 单实例激活 IPC 回归测试 — 确保后启动实例能唤起已运行实例的主窗口
// 关联文件:
//   lib/shared/services/single_instance_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/services/single_instance_service.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';

void main() {
  group('SingleInstanceService activation IPC', () {
    final reporter = _FailureReporter();
    Future<void> startServer() =>
        SingleInstanceService.startActivationServer(failureReporter: reporter);
    Future<InstanceActivationResult> notify({
      Duration timeout = const Duration(milliseconds: 400),
    }) => SingleInstanceService.notifyRunningInstance(
      timeout: timeout,
      failureReporter: reporter,
    );
    setUp(() async {
      reporter.failures.clear();
      // 清理静态状态与本测试创建的端口文件，避免用例间互相污染。
      await SingleInstanceService.unlock();
      SingleInstanceService.onActivate = null;
      final portFile = File(SingleInstanceService.portFilePath);
      if (portFile.existsSync()) {
        portFile.deleteSync();
      }
    });

    tearDown(() async {
      SingleInstanceService.onActivate = null;
      await SingleInstanceService.unlock();
    });

    test(
      'listener startup failure does not wait for reporting',
      () async {
        final preparingReport = Completer<void>();
        final configuration = Completer<void>();
        final uploaded = Completer<Map<String, dynamic>>();
        final client = MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          uploaded.complete(
            (payload['events'] as List).single as Map<String, dynamic>,
          );
          return http.Response('', 204);
        });
        final pendingReporter = StartupFailureReporter(
          httpClient: client,
          getDeviceId: () async => 'test',
          getBaseUrl: () => 'https://anonymous.example',
          getEnabled: () async {
            preparingReport.complete();
            await configuration.future;
            return true;
          },
        );
        final starting = IOOverrides.runZoned(
          () => SingleInstanceService.startActivationServer(
            failureReporter: pendingReporter,
          ),
          serverSocketBind:
              (
                address,
                port, {
                backlog = 0,
                v6Only = false,
                shared = false,
              }) async {
                throw const SocketException(
                  'Listener unavailable',
                  osError: OSError('Denied', 13),
                );
              },
        );
        try {
          await preparingReport.future.timeout(const Duration(seconds: 1));
          await starting.timeout(const Duration(milliseconds: 100));
          expect(configuration.isCompleted, isFalse);
          expect(uploaded.isCompleted, isFalse);
          expect(SingleInstanceService.activePort, isNull);
          expect(
            File(SingleInstanceService.portFilePath).existsSync(),
            isFalse,
          );
        } finally {
          configuration.complete();
          await starting;
          final event = await uploaded.future.timeout(
            const Duration(seconds: 1),
          );
          expect(event['error_code'], 'single_instance_listener');
          expect(
            event['exception_message'],
            contains('reason=listener_start_failed'),
          );
          expect(event['exception_message'], contains('os_code=13'));
          client.close();
        }
      },
    );

    test(
      'delivers activation request to the running instance callback',
      () async {
        await startServer();
        final activated = Completer<void>();
        SingleInstanceService.onActivate = () async {
          if (!activated.isCompleted) {
            activated.complete();
          }
        };

        final delivered = await notify();

        expect(delivered, InstanceActivationResult.activated);
        // 服务端处理连接是异步的，等回调真正执行再断言。
        await activated.future.timeout(const Duration(seconds: 2));
      },
    );

    test('does not claim activation when the window callback fails', () async {
      await startServer();
      SingleInstanceService.onActivate = () async {
        throw StateError('window could not be shown');
      };

      expect(await notify(), InstanceActivationResult.failed);
      expect(
        reporter.failures,
        contains('single_instance_activation:window_show_failed'),
      );
    });

    test('a still-starting owner at the deadline is not an error', () async {
      await startServer();

      expect(await notify(), InstanceActivationResult.starting);
      expect(reporter.failures, isEmpty);
      // 第二实例等待结束后，第一实例仍能完成启动并接受后续唤起。
      SingleInstanceService.onActivate = () async {};
      expect(await notify(), InstanceActivationResult.activated);
      expect(reporter.failures, isEmpty);
    });

    for (final (laterResponse, failureReason) in [
      ('failed', 'window_show_failed'),
      ('exiting', 'owner_exiting'),
      ('close', 'ack_missing'),
      ('hang', 'ack_timeout'),
    ]) {
      test('not_ready must not hide a later $laterResponse failure', () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        var requests = 0;
        final subscription = server.listen((socket) async {
          sockets.add(socket);
          await utf8.decoder.bind(socket).transform(const LineSplitter()).first;
          requests++;
          final response = requests == 1 ? 'not_ready' : laterResponse;
          if (response == 'hang') {
            return;
          }
          if (response != 'close') {
            socket.writeln(response);
            await socket.flush();
          }
          await socket.close();
        });
        try {
          await File(
            SingleInstanceService.portFilePath,
          ).writeAsString('${server.port}');
          expect(await notify(), InstanceActivationResult.failed);
          expect(requests, 2);
          expect(reporter.failures, [
            'single_instance_activation:$failureReason',
          ]);
        } finally {
          for (final socket in sockets) {
            socket.destroy();
          }
          await subscription.cancel();
          await server.close();
        }
      });
    }

    test(
      'waits for the window callback to finish before acknowledging',
      () async {
        await startServer();
        final showing = Completer<void>();
        final entered = Completer<void>();
        SingleInstanceService.onActivate = () {
          entered.complete();
          return showing.future;
        };
        var completed = false;
        final result = notify().then((value) {
          completed = true;
          return value;
        });
        await entered.future;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(completed, isFalse);
        showing.complete();
        expect(await result, InstanceActivationResult.activated);
        expect(reporter.failures, isEmpty);
      },
    );

    test('retries while the owner is still initializing its window', () async {
      await startServer();
      final result = notify();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      SingleInstanceService.onActivate = () async {};
      expect(await result, InstanceActivationResult.activated);
      expect(reporter.failures, isEmpty);
    });

    test('a non-owner cannot delete the running instance port', () async {
      final portFile = File(SingleInstanceService.portFilePath);
      await portFile.writeAsString('12345');
      await SingleInstanceService.unlock();
      expect(await portFile.readAsString(), '12345');
    });

    test(
      'a corrupt port file is reported separately from a missing owner',
      () async {
        await File(
          SingleInstanceService.portFilePath,
        ).writeAsString('not-a-port');
        final watch = Stopwatch()..start();
        expect(await notify(), InstanceActivationResult.failed);
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 400)),
        );
        expect(reporter.failures, ['single_instance_activation:port_invalid']);
      },
    );

    for (final partialContent in ['', 'not-a-port']) {
      test(
        'port publication recovers from incomplete content "$partialContent"',
        () async {
          await startServer();
          var activations = 0;
          SingleInstanceService.onActivate = () async {
            activations++;
          };
          final port = SingleInstanceService.activePort!;
          final file = File(SingleInstanceService.portFilePath);
          file.writeAsStringSync(partialContent);
          final publication = Future<void>.delayed(
            const Duration(milliseconds: 40),
            () {
              file.writeAsStringSync('$port');
            },
          );
          final activated = await notify();
          await publication;
          expect(activated, InstanceActivationResult.activated);
          expect(activations, 1);
          expect(reporter.failures, isEmpty);
        },
      );
    }

    test('port publication retries a Windows sharing violation', () async {
      await startServer();
      SingleInstanceService.onActivate = () async {};
      final file = _PortReadFile(
        File(SingleInstanceService.portFilePath),
        failures: 1,
      );
      final activated = await IOOverrides.runZoned(
        () => notify(),
        createFile: (_) => file,
      );
      expect(activated, InstanceActivationResult.activated);
      expect(file.reads, greaterThan(1));
      expect(reporter.failures, isEmpty);
    });

    test(
      'port publication waits for a transient numeric port until the deadline',
      () async {
        await startServer();
        SingleInstanceService.onActivate = () async {};
        final publishedPort = SingleInstanceService.activePort!;
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final incompletePort = probe.port;
        await probe.close();
        final file = File(SingleInstanceService.portFilePath);
        file.writeAsStringSync('$incompletePort');
        final publication = Future<void>.delayed(
          const Duration(milliseconds: 1300),
          () {
            file.writeAsStringSync('$publishedPort');
          },
        );
        final activated = await notify(timeout: const Duration(seconds: 3));
        await publication;
        expect(activated, InstanceActivationResult.activated);
        expect(reporter.failures, isEmpty);
      },
    );

    test(
      'port publication reports a persistent read failure only at deadline',
      () async {
        final file = _PortReadFile(
          File(SingleInstanceService.portFilePath),
          failures: 1000,
        );
        final watch = Stopwatch()..start();
        final activated = await IOOverrides.runZoned(
          () => notify(),
          createFile: (_) => file,
        );
        expect(activated, InstanceActivationResult.failed);
        expect(file.reads, greaterThan(1));
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 400)),
        );
        expect(reporter.failures, [
          'single_instance_activation:port_read_failed',
        ]);
      },
    );

    test(
      'a connected but unresponsive owner times out and reports once',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        final subscription = server.listen(sockets.add);
        try {
          await File(
            SingleInstanceService.portFilePath,
          ).writeAsString('${server.port}');
          expect(
            await notify(timeout: const Duration(milliseconds: 100)),
            InstanceActivationResult.failed,
          );
          expect(reporter.failures, ['single_instance_activation:ack_timeout']);
        } finally {
          for (final socket in sockets) {
            socket.destroy();
          }
          await subscription.cancel();
          await server.close();
        }
      },
    );

    test(
      'an old owner closing without acknowledgement is unconfirmed',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((socket) async {
          await socket.first;
          await socket.close();
        });
        try {
          await File(
            SingleInstanceService.portFilePath,
          ).writeAsString('${server.port}');
          expect(await notify(), InstanceActivationResult.failed);
          expect(reporter.failures, ['single_instance_activation:ack_missing']);
        } finally {
          await subscription.cancel();
          await server.close();
        }
      },
    );

    test('ignores commands other than the activate command', () async {
      await startServer();
      var activations = 0;
      SingleInstanceService.onActivate = () async {
        activations++;
      };

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        SingleInstanceService.activePort!,
      );
      socket.writeln('garbage');
      await socket.flush();
      // 服务端处理完连接后会主动关闭；drain 完成即代表命令已被读取。
      await socket.drain<void>().timeout(const Duration(seconds: 2));

      expect(activations, 0);
    });

    test(
      'returns failed when no instance published an activation port',
      () async {
        final delivered = await notify(
          timeout: const Duration(milliseconds: 300),
        );

        expect(delivered, InstanceActivationResult.failed);
      },
    );

    test('reports an unreachable port only after the retry deadline', () async {
      // 借一个临时端口再释放，得到几乎确定无人监听的端口，模拟崩溃残留。
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      await File(SingleInstanceService.portFilePath).writeAsString('$deadPort');

      final stopwatch = Stopwatch()..start();
      final delivered = await notify();
      stopwatch.stop();

      expect(delivered, InstanceActivationResult.failed);
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      expect(reporter.failures, [
        'single_instance_activation:port_unreachable',
      ]);
    });

    test('unlock stops the server and removes the port file', () async {
      await startServer();
      expect(File(SingleInstanceService.portFilePath).existsSync(), isTrue);

      await SingleInstanceService.unlock();

      expect(File(SingleInstanceService.portFilePath).existsSync(), isFalse);
      final delivered = await notify(
        timeout: const Duration(milliseconds: 300),
      );
      expect(delivered, InstanceActivationResult.failed);
    });
  });
}

class _FailureReporter extends StartupFailureReporter {
  final failures = <String>[];

  @override
  Future<void> reportLifecycleFailure({
    required String phase,
    required String reason,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    failures.add('$phase:$reason');
  }
}

/// 在 macOS 测试中复现 Windows 发布端口文件时的瞬时共享冲突。
class _PortReadFile implements File {
  _PortReadFile(this.file, {required this.failures});

  final File file;
  final int failures;
  int reads = 0;

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    reads++;
    if (reads <= failures) {
      throw const FileSystemException(
        'Sharing violation',
        '',
        OSError('Sharing violation', 32),
      );
    }
    return file.readAsStringSync(encoding: encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
