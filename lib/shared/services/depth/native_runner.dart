// 职责: 启动桌面深度子进程并转发结构化进度，取消时等待进程退出。
// 关联文件:
//   third/depth-native/main.cpp
//   lib/shared/services/depth/orchestrator.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../logger/app_logger.dart';
import '../production/ffmpeg_runner.dart';
import 'model.dart';

final _log = AppLogger.forModule('Depth');

class DepthNativeRunner {
  const DepthNativeRunner(this.executable);
  final String executable;
  static String bundledExecutable() => Platform.isMacOS
      ? p.normalize(
          p.join(
            p.dirname(Platform.resolvedExecutable),
            '../Resources/depth/bin/reveric-depth-native',
          ),
        )
      : p.join(
          p.dirname(Platform.resolvedExecutable),
          'depth',
          'bin',
          'reveric-depth-native.exe',
        );

  Future<void> run({
    required String model,
    required Directory workspace,
    required DepthProfile profile,
    required int frames,
    required MediaCancellation cancellation,
    required DepthProgress progress,
  }) async {
    checkDepthCancellation(cancellation);
    if (!await File(executable).exists()) {
      throw const DepthException(DepthFailure.unavailable);
    }
    final arguments = [
      '--job',
      model,
      p.join(workspace.path, 'input.rgb'),
      p.join(workspace.path, 'depth.f32'),
      p.join(workspace.path, 'depth.gray'),
      '${profile.width}',
      '${profile.height}',
      '$frames',
      '0',
    ];
    final process = await Process.start(executable, arguments);
    var diagnostics = '';
    var complete = false;
    final errors = process.stderr.transform(utf8.decoder).listen((chunk) {
      diagnostics += chunk;
      if (diagnostics.length > 8192) {
        diagnostics = diagnostics.substring(diagnostics.length - 8192);
      }
    });
    final events = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            if (event['stage'] == 'complete') {
              complete = true;
            }
            if (event['stage'] == 'inference' || event['stage'] == 'mapping') {
              progress(
                event['stage'] == 'inference'
                    ? DepthStage.inference
                    : DepthStage.mapping,
                (event['progress'] as num?)?.toDouble(),
              );
            }
          } catch (error) {
            _log.warning('invalid native progress record');
          }
        });
    final eventsDone = events.asFuture<void>();
    final errorsDone = errors.asFuture<void>();
    try {
      await cancellation.bind(() async {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () async {
            process.kill(ProcessSignal.sigkill);
            return process.exitCode;
          },
        );
      });
      final code = await process.exitCode;
      await eventsDone;
      await errorsDone;
      checkDepthCancellation(cancellation);
      if (code != 0 || !complete) {
        _log.error(
          'native exit=$code detail=${ffmpegFailureDetail(diagnostics, [executable, ...arguments])}',
        );
        throw const DepthException(DepthFailure.native_failed);
      }
    } finally {
      cancellation.unbind();
      await process.stdin.close();
      await events.cancel();
      await errors.cancel();
    }
  }
}
