// 职责: 执行可取消的原生媒体会话，保留命令退出码与日志，并为媒体业务转换失败。
// 关联文件:
//   lib/shared/services/production/media_service.dart
//   lib/shared/models/production/media.dart
//   lib/shared/services/production/runtime.dart

import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/abstract_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/level.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';
import '../../logger/app_logger.dart';
import '../../models/production/media.dart';
import 'runtime.dart';

final _log = AppLogger.forModule('Media');

/// FFmpegKit retains thread-local overwrite flags between executions. Reset
/// both through FFmpeg's boolean negation options before applying this call's
/// policy. FFprobe has no overwrite options and must not use this prefix.
List<String> ffmpegSessionArguments(List<String> arguments) => [
  '-noy',
  '-non',
  ...arguments,
];

/// FFprobe writes its machine output through FFmpegKit's STDERR channel.
/// Diagnostic levels (including the banner and warnings) are not JSON.
String ffmpegProbeOutput(Iterable<Log> logs) => logs
    .where((log) => log.getLevel() == Level.avLogStderr)
    .map((log) => log.getMessage())
    .join();

/// Keep native error details useful without retaining local paths or URLs.
String ffmpegFailureDetail(
  String output,
  List<String> arguments, {
  int limit = 4096,
}) {
  var detail = output;
  for (final argument in arguments) {
    if (argument.startsWith('/') ||
        argument.startsWith('\\\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(argument)) {
      detail = detail.replaceAll(argument, '<path>');
    }
  }
  detail = detail
      .replaceAll(RegExp(r'''[A-Za-z][A-Za-z0-9+.-]*://[^\s"']+'''), '<url>')
      .replaceAll(RegExp(r"'(/|[A-Za-z]:[\\/]|\\\\)[^'\r\n]*'"), "'<path>'")
      .replaceAll(RegExp(r'"(/|[A-Za-z]:[\\/]|\\\\)[^"\r\n]*"'), '"<path>"');
  return detail.length <= limit
      ? detail
      : '[truncated] ${detail.substring(detail.length - limit)}';
}

/// Read a completed native session for probe, frame and rendering operations.
Future<String> readFfmpegSessionOutput(
  AbstractSession session, {
  required bool probe,
  required MediaCancellation cancellation,
  required List<String> arguments,
}) async {
  final code = await session.getReturnCode();
  if (cancellation.cancelled || ReturnCode.isCancel(code)) {
    throw const MediaException(MediaFailure.cancelled);
  }
  if (!ReturnCode.isSuccess(code)) {
    final logs = await session.getAllLogs();
    final details = logs
        .where((log) => log.getLevel() <= Level.avLogError)
        .map((log) => log.getMessage())
        .join();
    final nativeLog = ffmpegFailureDetail(
      logs.map((log) => log.getMessage()).join(),
      arguments,
      limit: 65536,
    );
    final failure = code == null ? await session.getFailStackTrace() : null;
    final message = ffmpegFailureDetail(
      [
        if (details.trim().isNotEmpty) details.trim(),
        if (failure != null && failure.trim().isNotEmpty) failure.trim(),
      ].join('\n'),
      arguments,
    );
    _log.error(
      'native ${probe ? 'probe' : 'encode'} failed '
      'session=${session.getSessionId()} code=${code?.getValue()} '
      'detail=$message',
    );
    throw MediaException(
      probe ? MediaFailure.invalid_media : MediaFailure.encoding_failed,
      nativeSessionId: session.getSessionId(),
      nativeExitCode: code?.getValue(),
      message: message.isNotEmpty
          ? message
          : nativeLog.trim().isNotEmpty
          ? ffmpegFailureDetail(nativeLog.trim(), arguments)
          : null,
      nativeLog: nativeLog,
    );
  }
  return probe
      ? ffmpegProbeOutput(await session.getAllLogs())
      : (await session.getOutput()) ?? '';
}

class MediaCancellation {
  void Function(Duration processed)? onProgress;
  bool _cancelled = false;
  Future<void> Function()? _cancel;
  bool get cancelled => _cancelled;
  Future<void> cancel() async {
    _cancelled = true;
    await _cancel?.call();
  }

  Future<void> bind(Future<void> Function() cancel) async {
    _cancel = cancel;
    if (_cancelled) {
      await cancel();
    }
  }

  void unbind() => _cancel = null;
}

class FfmpegExecutionResult {
  const FfmpegExecutionResult({
    required this.exitCode,
    this.output = '',
    this.cancelled = false,
    this.errorCode,
    this.error,
  });

  static Future<FfmpegExecutionResult> fromSession(
    AbstractSession session, {
    required bool cancelled,
  }) async {
    int? code;
    var output = '';
    String? error;
    try {
      code = (await session.getReturnCode())?.getValue();
    } catch (failure) {
      error = failure.toString();
    }
    try {
      output = (await session.getOutput()) ?? '';
      if (code == null && error == null) {
        error = await session.getFailStackTrace();
      }
    } catch (failure) {
      error = [?error, failure.toString()].join('\n');
    }
    return FfmpegExecutionResult(
      exitCode: code,
      output: output,
      cancelled: cancelled || code == ReturnCode.cancel,
      errorCode: code == null || error != null ? 'execution_failed' : null,
      error: error,
    );
  }

  final int? exitCode;
  final String output;
  final bool cancelled;
  final String? errorCode, error;
}

class FfmpegRunner {
  static Future<void> _encodingTail = Future.value();

  Future<FfmpegExecutionResult> executeCommand(
    List<String> arguments, {
    required MediaCancellation cancellation,
  }) => _serialize(() => _executeCommand(arguments, cancellation));

  Future<FfmpegExecutionResult> _executeCommand(
    List<String> arguments,
    MediaCancellation cancellation,
  ) async {
    if (cancellation.cancelled) {
      return const FfmpegExecutionResult(exitCode: null, cancelled: true);
    }
    var started = false;
    try {
      await initializeMediaRuntime();
      if (cancellation.cancelled) {
        return const FfmpegExecutionResult(exitCode: null, cancelled: true);
      }
      final result = Completer<FfmpegExecutionResult>();
      Future<void> finish(AbstractSession session) async {
        final outcome = await FfmpegExecutionResult.fromSession(
          session,
          cancelled: cancellation.cancelled,
        );
        if (outcome.exitCode != 0) {
          _log.error(
            'native command failed session=${session.getSessionId()} '
            'code=${outcome.exitCode} detail=${ffmpegFailureDetail(outcome.output, arguments)}',
          );
        }
        result.complete(outcome);
      }

      final session = await FFmpegKit.executeWithArgumentsAsync(
        ffmpegSessionArguments(arguments),
        finish,
        null,
        (statistics) => cancellation.onProgress?.call(
          Duration(milliseconds: statistics.getTime().round()),
        ),
      );
      started = true;
      final id = session.getSessionId();
      if (id == null) {
        return const FfmpegExecutionResult(
          exitCode: null,
          errorCode: 'start_failed',
          error: 'FFmpegKit did not create a native session.',
        );
      }
      await cancellation.bind(() => FFmpegKit.cancel(id));
      return await result.future;
    } on UnsupportedError {
      rethrow;
    } catch (error) {
      return FfmpegExecutionResult(
        exitCode: null,
        cancelled: cancellation.cancelled,
        errorCode: started ? 'execution_failed' : 'start_failed',
        error: error.toString(),
      );
    } finally {
      cancellation.unbind();
    }
  }

  Future<String> execute(
    List<String> arguments, {
    required bool probe,
    required MediaCancellation cancellation,
  }) async {
    if (probe) {
      return _execute(arguments, probe: true, cancellation: cancellation);
    }
    return _serialize(
      () => _execute(arguments, probe: false, cancellation: cancellation),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() run) async {
    final previous = _encodingTail;
    final released = Completer<void>();
    _encodingTail = released.future;
    await previous;
    try {
      return await run();
    } finally {
      released.complete();
    }
  }

  Future<String> _execute(
    List<String> arguments, {
    required bool probe,
    required MediaCancellation cancellation,
  }) async {
    if (cancellation.cancelled) {
      throw const MediaException(MediaFailure.cancelled);
    }
    await initializeMediaRuntime();
    if (cancellation.cancelled) {
      throw const MediaException(MediaFailure.cancelled);
    }
    final result = Completer<String>();
    Future<void> finish(AbstractSession session) async {
      try {
        result.complete(
          await readFfmpegSessionOutput(
            session,
            probe: probe,
            cancellation: cancellation,
            arguments: arguments,
          ),
        );
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }

    final session = probe
        ? await FFprobeKit.executeWithArgumentsAsync(arguments, finish)
        : await FFmpegKit.executeWithArgumentsAsync(
            ffmpegSessionArguments(arguments),
            finish,
            null,
            (statistics) => cancellation.onProgress?.call(
              Duration(milliseconds: statistics.getTime().round()),
            ),
          );
    final id = session.getSessionId();
    if (id == null) {
      throw const MediaException(MediaFailure.encoding_failed);
    }
    await cancellation.bind(() => FFmpegKit.cancel(id));
    try {
      return await result.future;
    } finally {
      cancellation.unbind();
    }
  }
}
