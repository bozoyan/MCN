// 职责: 编排可取消的逐段朗读、单段预取、有界缓存与串行播放器切换。
// 关联文件:
//   lib/shared/models/narration.dart
//   lib/desktop/features/narration/player.dart
//   lib/desktop/features/narration/playback.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../logger/app_logger.dart';
import '../../models/narration.dart';
import '../../models/audio/exception.dart';

final _log = AppLogger.forModule('Narration');

class NarrationAudio {
  const NarrationAudio(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// 播放器只报告完成和失败；高频位置更新由播放控件独立订阅。
abstract interface class NarrationPlayer {
  Future<void> play();
  Future<void> pause();
  Future<void> setSpeed(double speed);
  Future<void> dispose();
  void onFinished(void Function(Object? error) callback);
}

typedef NarrationGenerate =
    Future<NarrationAudio> Function(
      NarrationSegment segment,
      Future<void> abort,
    );

class NarrationOrchestrator extends ChangeNotifier {
  late List<NarrationSegment> segments;
  late NarrationGenerate _generate;
  late Future<NarrationPlayer> Function(NarrationAudio) _createPlayer;
  final _cache = <(String, String, String), _AudioResult>{};
  final _requests = <(String, String, String), _PendingAudio>{};
  Future<void> _transport = Future.value();
  NarrationPlayer? _player;
  int _cacheBytes = 0;
  int _epoch = 0;
  int index = 0;
  bool playing = false;
  bool loading = false;
  bool completed = false;
  bool _closed = false;
  double speed = 1;
  Object? error;

  static const cacheLimit = 64 * 1024 * 1024;

  void configure({
    required List<NarrationSegment> segments,
    required NarrationGenerate generate,
    required Future<NarrationPlayer> Function(NarrationAudio) createPlayer,
  }) {
    if (segments.isEmpty) {
      throw const AudioException('narration_empty');
    }
    this.segments = List.unmodifiable(segments);
    _generate = generate;
    _createPlayer = createPlayer;
  }

  void play({bool retry = false}) {
    if (_closed || playing) {
      return;
    }
    if (completed) {
      index = 0;
      completed = false;
    }
    if (retry) {
      final key = segments[index].cacheKey;
      // 播放器故障不代表语音生成失败，重试时沿用已付费的音频。
      if (_cache[key]?.error != null) {
        _cache.remove(key);
      }
    }
    error = null;
    playing = true;
    final epoch = ++_epoch;
    final player = _player;
    if (player != null) {
      unawaited(
        _enqueue(() async {
          if (!_current(epoch)) {
            return;
          }
          await player.play();
          if (_current(epoch)) {
            _prefetch();
          }
        }, epoch),
      );
    } else {
      unawaited(_open(epoch));
    }
    _notify();
  }

  void pause() {
    if (_closed || !playing) {
      return;
    }
    playing = false;
    loading = false;
    final epoch = ++_epoch;
    // 已提交的生成允许完成并缓存；暂停期间不发起新的预取。
    final player = _player;
    if (player != null) {
      unawaited(_enqueue(player.pause, epoch));
    }
    _notify();
  }

  void jump(int target) {
    if (_closed || target < 0 || target >= segments.length) {
      return;
    }
    final epoch = ++_epoch;
    index = target;
    completed = false;
    error = null;
    loading = false;
    _releasePlayer(epoch);
    final keep = segments[target].cacheKey;
    for (final entry in _requests.entries.toList()) {
      if (entry.key != keep) {
        entry.value.cancel();
        _requests.remove(entry.key);
      }
    }
    if (playing) {
      unawaited(_open(epoch));
    }
    _notify();
  }

  void setSpeed(double value) {
    if (_closed || !value.isFinite || value < 0.5 || value > 2) {
      return;
    }
    speed = value;
    final player = _player;
    if (player != null) {
      unawaited(_enqueue(() => player.setSpeed(value), _epoch));
    }
    _notify();
  }

  bool _current(int epoch) => !_closed && epoch == _epoch;

  Future<void> _open(int epoch) async {
    loading = true;
    _notify();
    final result = await _load(segments[index]);
    if (!_current(epoch) || !playing) {
      return;
    }
    if (result.error != null) {
      _fail(result.error!, epoch);
      return;
    }
    await _enqueue(() async {
      if (!_current(epoch) || !playing) {
        return;
      }
      final player = await _createPlayer(result.audio!);
      if (!_current(epoch) || !playing) {
        await player.dispose();
        return;
      }
      _player = player;
      player.onFinished((failure) {
        if (_closed || !identical(_player, player)) {
          return;
        }
        if (failure != null) {
          _fail(failure, _epoch);
        } else if (playing) {
          if (index + 1 < segments.length) {
            jump(index + 1);
          } else {
            playing = false;
            completed = true;
            _releasePlayer(++_epoch);
            _notify();
          }
        }
      });
      await player.setSpeed(speed);
      if (!_current(epoch) || !playing) {
        return;
      }
      await player.play();
      if (_current(epoch)) {
        loading = false;
        _notify();
        _prefetch();
      }
    }, epoch);
  }

  void _prefetch() {
    if (!_closed && playing && index + 1 < segments.length) {
      unawaited(_load(segments[index + 1]));
    }
  }

  Future<_AudioResult> _load(NarrationSegment segment) {
    final key = segment.cacheKey;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    final existing = _requests[key];
    if (existing != null) {
      return existing.result;
    }
    final pending = _PendingAudio();
    _requests[key] = pending;
    pending.result = () async {
      _AudioResult result;
      try {
        final audio = await _generate(segment, pending.abort.future);
        result = _AudioResult(audio: audio);
      } catch (failure, stack) {
        if (!pending.cancelled && !_closed) {
          _log.error('generation failed', error: failure, stackTrace: stack);
        }
        result = _AudioResult(error: failure);
      }
      if (identical(_requests[key], pending)) {
        _requests.remove(key);
      }
      if (!_closed && !pending.cancelled) {
        final bytes = result.audio?.bytes.length ?? 0;
        if (bytes <= cacheLimit) {
          while (_cache.isNotEmpty && _cacheBytes + bytes > cacheLimit) {
            _cacheBytes -=
                _cache.remove(_cache.keys.first)!.audio?.bytes.length ?? 0;
          }
          _cache[key] = result;
          _cacheBytes += bytes;
        }
      }
      return result;
    }();
    return pending.result;
  }

  Future<void> _enqueue(Future<void> Function() action, int epoch) {
    _transport = _transport.then((_) => action()).catchError((
      Object failure,
      StackTrace stack,
    ) {
      _log.error('playback failed', error: failure, stackTrace: stack);
      _fail(failure, epoch);
    });
    return _transport;
  }

  void _releasePlayer(int epoch) {
    final previous = _player;
    _player = null;
    if (previous != null) {
      unawaited(_enqueue(previous.dispose, epoch));
    }
  }

  void _fail(Object failure, int epoch) {
    if (!_current(epoch)) {
      return;
    }
    playing = loading = false;
    error = failure;
    _releasePlayer(++_epoch);
    _notify();
  }

  void _notify() {
    if (!_closed) {
      notifyListeners();
    }
  }

  /// 供关闭路径与测试等待已开始的原生播放器操作释放。
  Future<void> get settled => _transport;

  @override
  void dispose() {
    _closed = true;
    ++_epoch;
    playing = loading = false;
    for (final request in _requests.values) {
      request.cancel();
    }
    _requests.clear();
    _cache.clear();
    _cacheBytes = 0;
    _releasePlayer(_epoch);
    super.dispose();
  }
}

class _PendingAudio {
  final abort = Completer<void>();
  late Future<_AudioResult> result;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    if (!abort.isCompleted) {
      abort.complete();
    }
  }
}

class _AudioResult {
  const _AudioResult({this.audio, this.error});
  final NarrationAudio? audio;
  final Object? error;
}
