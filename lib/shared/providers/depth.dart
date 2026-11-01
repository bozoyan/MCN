// 职责: 装配唯一桌面深度任务控制器和模型源，跨页面持有任务资源。
// 关联文件:
//   lib/shared/services/depth/task_controller.dart
//   lib/shared/providers/video_tasks.dart
//   lib/shared/utils/storage_paths.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/depth/model.dart';
import '../services/depth/model_service.dart';
import '../services/depth/native_runner.dart';
import '../services/depth/task_controller.dart';
import '../services/production/ffmpeg_runner.dart';
import '../utils/storage_paths.dart';
import '../logger/app_logger.dart';
import '../services/system_tray_service.dart';
import 'video_tasks.dart';
import 'settings_providers.dart';
import '../services/proxy_client.dart';

final _log = AppLogger.forModule('Depth');

final depthTaskProvider = Provider<DepthTaskController>((ref) {
  final results = ref.watch(productionResultServiceProvider);
  const configuredSource = String.fromEnvironment('REVERIC_DEPTH_MODEL_SOURCE');
  final environmentSource =
      Platform.environment['REVERIC_DEPTH_MODEL_SOURCE'] ?? '';
  final source = configuredSource.isNotEmpty
      ? configuredSource
      : environmentSource.isNotEmpty
      ? environmentSource
      : DepthModelManifest.defaultSource;
  final controller = DepthTaskController(
    root: Directory(p.join(RevericPaths.supportRoot, 'cache', 'depth')),
    models: DepthModelService(
      Directory(p.join(RevericPaths.supportRoot, 'cache', 'modles')),
      DepthModelManifest(source: source),
      createClient: () async => createProxyHttpClient(
        (await ref.read(appSettingsProvider.future)).networkProxy,
      ),
    ),
    native: DepthNativeRunner(
      Platform.environment['REVERIC_DEPTH_EXECUTABLE'] ??
          DepthNativeRunner.bundledExecutable(),
    ),
    resolve: results.resolve,
    release: (service) => results.release!(service),
    ffmpeg: FfmpegRunner(),
  );
  ref.onDispose(() => unawaited(controller.dispose()));
  final unregister = SystemTrayService().registerExitGuard(() async {
    await controller.stop();
    return true;
  });
  ref.onDispose(unregister);
  unawaited(
    controller.initialize().catchError((Object error, StackTrace stack) {
      _log.error('task recovery failed', error: error, stackTrace: stack);
    }),
  );
  return controller;
});
