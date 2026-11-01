// 职责: 单实例服务 — 通过文件锁确保仅运行一个应用实例，并为后启动实例提供唤起主窗口的 IPC 通道
// 关联文件:
//   lib/main.dart
//   lib/shared/services/system_tray_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logger/app_logger.dart';
import '../logger/startup_failure_reporter.dart';

final _log = AppLogger.forModule('SingleInstance');

enum InstanceActivationResult { activated, starting, failed }

class SingleInstanceService {
  static RandomAccessFile? _lockFile;
  static ServerSocket? _activationServer;
  static Future<void> Function()? _onActivate;
  static bool _stopping = false;
  static Future<void>? _unlocking;
  static Object? _lockError;

  /// 后启动实例请求唤起主窗口时发送的单行命令。
  @visibleForTesting
  static const String activateCommand = 'show';

  static String get _buildMode {
    if (kReleaseMode) {
      return 'release';
    }
    if (kProfileMode) {
      return 'profile';
    }
    return 'debug';
  }

  static String get _lockFilePath {
    final dir = Directory.systemTemp.path;
    return '$dir${Platform.pathSeparator}reveric-$_buildMode-instance.lock';
  }

  /// 激活端口 sidecar 文件：记录第一实例的监听端口，供后启动实例读取。
  /// 不写进锁文件本身——Windows 上独占锁会阻止其它进程读取锁文件内容。
  static String get _portFilePath => '$_lockFilePath.port';

  @visibleForTesting
  static String get portFilePath => _portFilePath;

  @visibleForTesting
  static int? get activePort => _activationServer?.port;

  static bool tryLock() {
    try {
      final file = File(_lockFilePath);
      _lockFile = file.openSync(mode: FileMode.write);
      _lockFile!.lockSync(FileLock.exclusive);
      _lockError = null;
      _log.checkpoint('instance lock acquired pid=$pid');
      return true;
    } catch (e) {
      _lockError = e;
      final lockFile = _lockFile;
      _lockFile = null;
      try {
        lockFile?.closeSync();
      } catch (closeError) {
        _log.warning(
          'Failed to close lock after acquisition failure: $closeError',
        );
      }
      _log.error('Failed to acquire lock', error: e);
      return false;
    }
  }

  /// 第一实例：启动激活监听。之后启动的实例抢锁失败时会连接该端口，
  /// 请求本实例唤起主窗口。监听失败保留窗口启动，并单独上报无法被唤起的原因。
  static Future<void> startActivationServer({
    StartupFailureReporter? failureReporter,
  }) async {
    if (_activationServer != null) {
      return;
    }

    ServerSocket? server;
    final portFile = File(_portFilePath);
    try {
      // A previous crash can leave the sidecar behind. The lock proves that
      // this process is now the owner, so remove it before publishing a new
      // port and avoid exposing the old value during bind.
      if (portFile.existsSync()) {
        portFile.deleteSync();
      }

      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await portFile.writeAsString('${server.port}', flush: true);
      _activationServer = server;
      _stopping = false;
      _log.info('Activation server listening on 127.0.0.1:${server.port}');
      unawaited(_serveActivationRequests(server, failureReporter));
    } catch (e, stack) {
      _activationServer = null;
      try {
        await server?.close().timeout(const Duration(seconds: 2));
      } catch (closeError) {
        _log.warning(
          'Failed to close activation server after startup failure: $closeError',
        );
      }
      try {
        if (portFile.existsSync()) {
          portFile.deleteSync();
        }
      } catch (deleteError) {
        _log.warning(
          'Failed to remove activation port after startup failure: $deleteError',
        );
      }
      _log.error('Failed to start activation server', error: e);
      // 监听失败不阻止本实例显示窗口；配置加载和网络上报不能阻塞 runApp。
      // reportLifecycleFailure 内部处理上报异常，后台执行不会产生未捕获错误。
      unawaited(
        (failureReporter ?? StartupFailureReporter()).reportLifecycleFailure(
          phase: 'single_instance_listener',
          reason: 'listener_start_failed',
          error: e,
          stackTrace: stack,
        ),
      );
    }
  }

  /// 注册唤起主窗口的回调；窗口就绪后由应用入口注入。
  static set onActivate(Future<void> Function()? callback) {
    _onActivate = callback;
  }

  static Future<void> _serveActivationRequests(
    ServerSocket server,
    StartupFailureReporter? failureReporter,
  ) async {
    try {
      await for (final socket in server) {
        unawaited(_handleActivationRequest(socket, failureReporter));
      }
    } catch (e, stack) {
      _log.error('Activation server stopped unexpectedly', error: e);
      await (failureReporter ?? StartupFailureReporter())
          .reportLifecycleFailure(
            phase: 'single_instance_listener',
            reason: 'listener_stopped',
            error: e,
            stackTrace: stack,
          );
    }
  }

  static Future<void> _handleActivationRequest(
    Socket socket,
    StartupFailureReporter? failureReporter,
  ) async {
    var stage = 'request_read';
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      if (line.trim() != activateCommand) {
        return;
      }
      final callback = _onActivate;
      if (callback == null || _stopping) {
        // 让请求方区分启动未就绪和退出中；不再丢弃请求后宣称成功。
        socket.writeln(_stopping ? 'exiting' : 'not_ready');
        await socket.flush();
        return;
      }
      _log.checkpoint('activation received pid=$pid stage=show_window');
      stage = 'window_show';
      await callback().timeout(const Duration(seconds: 2));
      stage = 'ack_write';
      socket.writeln('shown');
      await socket.flush();
      _log.checkpoint('activation completed pid=$pid stage=shown');
    } catch (e, stack) {
      _log.error(
        'Failed to handle activation request',
        error: e,
        stackTrace: stack,
      );
      // 客户端先收到结果；上报不能拖住唤起协议。
      try {
        socket.writeln('failed');
        await socket.flush().timeout(const Duration(seconds: 1));
      } catch (sendError) {
        _log.warning('Activation failure response unavailable: $sendError');
      }
      await (failureReporter ?? StartupFailureReporter())
          .reportLifecycleFailure(
            phase: stage == 'window_show'
                ? 'single_instance_window_show'
                : 'single_instance_protocol',
            reason: '${stage}_${e is TimeoutException ? 'timeout' : 'failed'}',
            error: e,
            stackTrace: stack,
          );
    } finally {
      socket.destroy();
    }
  }

  /// 后启动实例：区分窗口已显示、第一实例仍在启动和唤起失败。
  /// 启动中由第一实例继续显示窗口，不当作错误；TCP 写入成功本身不是显示确认。
  static Future<InstanceActivationResult> notifyRunningInstance({
    Duration timeout = const Duration(seconds: 5),
    StartupFailureReporter? failureReporter,
  }) async {
    final deadline = DateTime.now().add(timeout);
    int? unreachablePort;
    var reason = 'port_missing';
    Object lastError = _lockError ?? StateError('Activation port unavailable');
    var lastStack = StackTrace.current;
    final stopwatch = Stopwatch()..start();
    _log.checkpoint('activation requested pid=$pid stage=connect');
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      int? port;
      try {
        port = _readActivationPort();
        if (port == null) {
          reason = 'port_missing';
          lastError = _lockError ?? StateError('Activation port unavailable');
          lastStack = StackTrace.current;
        }
      } catch (error, stack) {
        // 发布端口文件要经过截断和写入；空内容、半写及 Windows 共享冲突
        // 都可能只是瞬态。保留诊断，统一到 deadline 后才判定失败。
        reason = error is FormatException ? 'port_invalid' : 'port_read_failed';
        lastError = error;
        lastStack = stack;
      }
      if (port == null) {
        unreachablePort = null;
      }
      if (port != null) {
        Socket? socket;
        try {
          socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(milliseconds: 500),
          );
          socket.writeln(activateCommand);
          await socket.flush();
          reason = 'ack_timeout';
          final response = await utf8.decoder
              .bind(socket)
              .transform(const LineSplitter())
              .first
              .timeout(deadline.difference(DateTime.now()));
          if (response == 'shown') {
            _log.checkpoint(
              'activation acknowledged pid=$pid elapsed_ms=${stopwatch.elapsedMilliseconds}',
            );
            return InstanceActivationResult.activated;
          }
          reason = switch (response) {
            'not_ready' => 'window_not_ready',
            'exiting' => 'owner_exiting',
            'failed' => 'window_show_failed',
            _ => 'invalid_ack',
          };
          lastError = StateError(reason);
          lastStack = StackTrace.current;
          if (response != 'not_ready') {
            break;
          }
        } catch (e, stack) {
          lastError = e;
          lastStack = stack;
          if (socket != null) {
            reason = e is TimeoutException ? 'ack_timeout' : 'ack_missing';
            break;
          }
          reason = 'port_unreachable';
          // 半写的数字也可能是合法端口；和读文件失败共用总 deadline，
          // 不另设更短的期限而抢先判错。同一端口只记录一次连接失败。
          if (unreachablePort != port) {
            unreachablePort = port;
            _log.warning('Activation port $port unreachable; retrying: $e');
          }
        } finally {
          socket?.destroy();
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (reason == 'window_not_ready') {
      _log.checkpoint(
        'activation deferred pid=$pid reason=$reason elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      return InstanceActivationResult.starting;
    }
    _log.checkpoint(
      'activation failed pid=$pid reason=$reason elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    await (failureReporter ?? StartupFailureReporter()).reportLifecycleFailure(
      phase: 'single_instance_activation',
      reason: reason,
      error: lastError,
      stackTrace: lastStack,
    );
    return InstanceActivationResult.failed;
  }

  static int? _readActivationPort() {
    try {
      final port = int.tryParse(File(_portFilePath).readAsStringSync().trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('Invalid activation port');
      }
      return port;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) {
        return null;
      }
      rethrow;
    }
  }

  static Future<void> unlock() => _unlocking ??= _unlock().whenComplete(() {
    _unlocking = null;
  });

  static Future<void> _unlock() async {
    // 抢锁失败的第二实例不能删除真正持锁实例的端口文件。
    if (_lockFile == null && _activationServer == null) {
      return;
    }
    _stopping = true;
    _log.checkpoint('instance cleanup started pid=$pid');
    _onActivate = null;
    final server = _activationServer;
    _activationServer = null;
    try {
      await server?.close().timeout(const Duration(seconds: 2));
    } catch (e) {
      _log.error('Failed to close activation server', error: e);
      // 关闭监听失败也必须继续释放本进程的锁；调用方负责退出结果上报。
      rethrow;
    } finally {
      _releaseLock();
    }
  }

  static void _releaseLock() {
    final lockFile = _lockFile;
    _lockFile = null;
    Object? portError;
    StackTrace? portStack;
    try {
      final portFile = File(_portFilePath);
      if (portFile.existsSync()) {
        portFile.deleteSync();
      }
    } catch (e, stack) {
      _log.error('Failed to delete activation port file', error: e);
      portError = e;
      portStack = stack;
    }
    try {
      lockFile?.closeSync();
    } catch (e) {
      _log.error('Failed to release lock', error: e);
      rethrow;
    }
    if (portError != null) {
      Error.throwWithStackTrace(portError, portStack!);
    }
    _log.checkpoint('instance cleanup completed pid=$pid');
  }
}
