// 职责: 装配媒体导入、探测编码、单播放器、自定义风格依赖及统一资产列表流。
// 关联文件:
//   lib/shared/services/production/library_service.dart
//   lib/shared/services/production/media_service.dart
//   lib/shared/services/production/ffmpeg_runner.dart
//   lib/shared/services/production/playback_service.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/service-naming.md

import 'dart:async';
import 'dart:io';
import '../database/app_database.dart';
import '../utils/storage_paths.dart';
import '../services/production/library_service.dart';
import '../services/production/style_service.dart';
import 'novel_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/production/ffmpeg_runner.dart';
import '../services/production/media_service.dart';
import '../services/production/playback_service.dart';

final mediaServiceProvider = Provider<MediaService>(
  (ref) => MediaService(FfmpegRunner()),
);
final productionStyleServiceProvider = Provider<ProductionStyleService>(
  (ref) => ProductionStyleService(ref.watch(appDatabaseProvider)),
);
final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final mediaLibraryServiceProvider = Provider<MediaLibraryService>(
  (ref) => MediaLibraryService(
    ref.watch(appDatabaseProvider),
    ref.watch(mediaServiceProvider),
    Directory(RevericPaths.fileWorkspaceParent),
  ),
);
final mediaAssetsProvider = StreamProvider.autoDispose<List<AssetRow>>(
  (ref) => ref.watch(appDatabaseProvider).assetDao.watchAssets(),
);
