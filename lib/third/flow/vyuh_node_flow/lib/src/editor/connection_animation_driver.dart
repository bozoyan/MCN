// 职责: 按指定帧率推进连线装饰动画，并在停用或隐藏时取消帧驱动。
// 关联文件:
//   lib/third/flow/vyuh_node_flow/lib/src/editor/node_flow_editor.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/layers/connections_layer.dart
// 遵循的 Rules:
//   .agents/rules/performance.md

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps connection decoration independent of the viewport's full-rate ticker.
class ConnectionAnimationDriver with WidgetsBindingObserver {
  ConnectionAnimationDriver(this.animation) {
    WidgetsBinding.instance.addObserver(this);
  }

  final AnimationController animation;
  Timer? _timer;
  bool _running = false;
  bool _enabled = false;
  int? _frameRate;
  Duration? _duration;

  void update({
    required bool running,
    required bool enabled,
    required int? frameRate,
  }) {
    assert(frameRate == null || frameRate > 0);
    if (_running == running &&
        _enabled == enabled &&
        _frameRate == frameRate &&
        _duration == animation.duration) {
      return;
    }
    _running = running;
    _enabled = enabled;
    _frameRate = frameRate;
    _duration = animation.duration;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    animation.stop();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_running ||
        !_enabled ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      return;
    }
    final frameRate = _frameRate;
    if (frameRate == null) {
      animation.repeat();
      return;
    }

    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / frameRate).ceil(),
    );
    final initialValue = animation.value;
    final period = animation.duration!.inMicroseconds;
    assert(period > 0);
    // A periodic timer advances the value without starting a vsync ticker.
    // tick includes missed intervals, so a busy frame does not slow the flow.
    _timer = Timer.periodic(interval, (timer) {
      animation.value =
          (initialValue + timer.tick * interval.inMicroseconds / period) % 1;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _restart();

  void dispose() {
    _timer?.cancel();
    _timer = null;
    animation.stop();
    WidgetsBinding.instance.removeObserver(this);
  }
}
