// 职责: 内存诊断日志 — 记录进程内存、Flutter 图片缓存、解码尺寸、surface 与媒体事件。
// 关联文件:
//   lib/shared/widgets/app_background.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/desktop/widgets/novel_list.dart
//   lib/shared/logger/app_logger.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../logger/app_logger.dart';

final _log = AppLogger.forModule('MEMORY');

class MemoryDebug {
  MemoryDebug._();

  static final Map<String, DateTime> _lastSnapshotAt = {};
  static final Set<String> _imageProbeKeys = {};
  static final Set<String> _fileProbeKeys = {};

  static void logProcessSnapshot(
    String label, {
    Duration minInterval = const Duration(seconds: 5),
  }) {
    final now = DateTime.now();
    final key = 'process:$label';
    final last = _lastSnapshotAt[key];
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastSnapshotAt[key] = now;

    _log.info(
      '[process] label=$label '
      'pid=$pid '
      'rss=${_formatBytes(ProcessInfo.currentRss)} '
      'maxRss=${_formatBytes(ProcessInfo.maxRss)}',
    );
  }

  static void logImageCacheSnapshot(
    String label, {
    Duration minInterval = const Duration(seconds: 5),
  }) {
    final now = DateTime.now();
    final last = _lastSnapshotAt[label];
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastSnapshotAt[label] = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cache = PaintingBinding.instance.imageCache;
      _log.info(
        '[image_cache] label=$label '
        'count=${cache.currentSize} '
        'bytes=${_formatBytes(cache.currentSizeBytes)} '
        'maxCount=${cache.maximumSize} '
        'maxBytes=${_formatBytes(cache.maximumSizeBytes)} '
        'live=${cache.liveImageCount} '
        'pending=${cache.pendingImageCount}',
      );
    });
  }

  static void logSurfaceEstimate({
    required BuildContext context,
    required String label,
    int surfaces = 1,
    String? note,
    Duration minInterval = const Duration(seconds: 5),
  }) {
    final now = DateTime.now();
    final key = 'surface:$label';
    final last = _lastSnapshotAt[key];
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastSnapshotAt[key] = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final view = View.maybeOf(context);
      final dpr =
          view?.devicePixelRatio ?? MediaQuery.devicePixelRatioOf(context);
      final logicalSize = MediaQuery.sizeOf(context);
      final physicalWidth = (logicalSize.width * dpr).round();
      final physicalHeight = (logicalSize.height * dpr).round();
      final bytesPerSurface = physicalWidth * physicalHeight * 4;
      _log.info(
        '[surface] label=$label '
        'logical=${logicalSize.width.toStringAsFixed(0)}x${logicalSize.height.toStringAsFixed(0)} '
        'dpr=${dpr.toStringAsFixed(2)} '
        'physical=${physicalWidth}x$physicalHeight '
        'surfaces=$surfaces '
        'estimatedRgba=${_formatBytes(bytesPerSurface * surfaces)}'
        '${note == null ? '' : ' note=$note'}',
      );
    });
  }

  static void logMediaEvent(
    String label, {
    Map<String, Object?> details = const {},
  }) {
    final suffix = details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    _log.info('[media] label=$label${suffix.isEmpty ? '' : ' $suffix'}');
    logProcessSnapshot('media:$label');
    logImageCacheSnapshot('media:$label');
  }

  static void logDecodedUiImage({
    required String label,
    required int width,
    required int height,
    int? sourceBytes,
  }) {
    final decodedBytes = width * height * 4;
    _log.info(
      '[ui_image_decode] label=$label '
      'decoded=${width}x$height '
      'estimatedRgba=${_formatBytes(decodedBytes)}'
      '${sourceBytes == null ? '' : ' sourceBytes=${_formatBytes(sourceBytes)}'}',
    );
    logProcessSnapshot('after_ui_image_decode:$label');
    logImageCacheSnapshot('after_ui_image_decode:$label');
  }

  static void logImageProvider({
    required String label,
    required ImageProvider provider,
    ImageConfiguration configuration = ImageConfiguration.empty,
    bool once = true,
  }) {
    final key = '$label|${provider.runtimeType}|$provider';
    if (once && !_imageProbeKeys.add(key)) {
      return;
    }

    late final ImageStreamListener listener;
    final stream = provider.resolve(configuration);
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        stream.removeListener(listener);
        final image = imageInfo.image;
        final decodedBytes = image.width * image.height * 4;
        _log.info(
          '[image_decode] label=$label '
          'provider=${provider.runtimeType} '
          'decoded=${image.width}x${image.height} '
          'estimatedRgba=${_formatBytes(decodedBytes)} '
          'scale=${imageInfo.scale} '
          'sync=$synchronousCall',
        );
        logProcessSnapshot('after_image_decode:$label');
        logImageCacheSnapshot('after_image_decode:$label');
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        _log.warning(
          '[image_decode_error] label=$label '
          'provider=${provider.runtimeType} error=$error',
        );
      },
    );
    stream.addListener(listener);
  }

  static void logFileImage({
    required String label,
    required File file,
    required ImageProvider provider,
    ImageConfiguration configuration = ImageConfiguration.empty,
    bool once = true,
  }) {
    final key = '$label|${file.path}';
    if (once && !_fileProbeKeys.add(key)) {
      return;
    }

    final stat = file.existsSync() ? file.statSync() : null;
    _log.info(
      '[image_file] label=$label '
      'exists=${stat != null} '
      'fileBytes=${stat == null ? 'n/a' : _formatBytes(stat.size)} '
      'path=${file.path}',
    );
    logImageProvider(
      label: label,
      provider: provider,
      configuration: configuration,
      once: once,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${bytes}B';
  }
}
