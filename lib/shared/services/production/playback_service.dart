// 职责: 串行切换桌面预览的 FVP 播放会话，并按预览拥有者释放解码资源。
// 关联文件:
//   lib/shared/providers/production_media.dart
//   lib/shared/services/production/media_service.dart
//   lib/shared/services/production/runtime.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'runtime.dart';

class PlaybackService {
  VideoPlayerController? _player;
  String? _owner;
  Future<void> _pending = Future.value();
  bool _disposed = false;

  /// 当前画面属于哪个拥有者；换人打开或释放前先置空，旧拥有者据此停用已失效的 [player]。
  final active = ValueNotifier<String?>(null);

  VideoPlayerController get player {
    if (_disposed) {
      throw StateError('Playback service disposed');
    }
    return _player ?? (throw StateError('No media is open'));
  }

  Future<void> open({
    required String owner,
    required String path,
    bool play = false,
  }) {
    if (_disposed) {
      throw StateError('Playback service disposed');
    }
    _owner = owner;
    final operation = _pending.then((_) async {
      if (_disposed || _owner != owner) {
        return;
      }
      if (!await File(path).exists()) {
        throw FileSystemException('Media file is missing');
      }
      await initializeMediaRuntime();
      final previous = _player;
      _player = null;
      active.value = null;
      await previous?.dispose();
      if (_disposed || _owner != owner) {
        return;
      }
      final next = VideoPlayerController.file(File(path));
      try {
        await next.initialize();
        if (_disposed || _owner != owner) {
          await next.dispose();
          return;
        }
        _player = next;
        active.value = owner;
        if (play) {
          await next.play();
        }
      } catch (_) {
        if (identical(_player, next)) {
          _player = null;
          active.value = null;
        }
        await next.dispose();
        rethrow;
      }
    });
    // Preserve errors for the caller while allowing the next explicit open.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> release(String owner) async {
    if (_owner != owner) {
      return;
    }
    _owner = null;
    await _pending;
    if (_owner == null) {
      final previous = _player;
      _player = null;
      active.value = null;
      await previous?.dispose();
    }
  }

  Future<void> playOrPause() =>
      player.value.isPlaying ? player.pause() : player.play();

  Future<void> dispose() async {
    _disposed = true;
    _owner = null;
    await _pending;
    active.value = null;
    await _player?.dispose();
    active.dispose();
  }
}
