// 职责: 为循环状态动画提供共享的限帧时钟，并让 State 按 TickerMode 自动挂载与释放。
// 关联文件:
//   lib/shared/components/reveric_spinner.dart
//   lib/shared/widgets/ai/chat/typing_indicator.dart
// 遵循的 Rules:
//   .agents/rules/performance.md

import 'dart:async';

import 'package:flutter/widgets.dart';

/// One low-rate clock shared by every looping status animation.
///
/// Status loops (spinners, typing dots, pulses) can stay visible for a whole
/// agent turn. A vsync ticker per loop requests a frame at display refresh
/// rate, and every frame re-rasterizes the whole window. Sharing this clock
/// caps all of them at [frameRate] and lands their repaints on the same frames.
final class StatusAnimationClock extends ChangeNotifier {
  StatusAnimationClock._();

  static final instance = StatusAnimationClock._();

  static const int frameRate = 15;

  static const interval = Duration(
    microseconds: Duration.microsecondsPerSecond ~/ frameRate,
  );

  Timer? _timer;
  int _clients = 0;
  int _ticks = 0;

  double get seconds =>
      _ticks * interval.inMicroseconds / Duration.microsecondsPerSecond;

  void attach() {
    _clients++;
    if (_timer != null) {
      return;
    }
    // A periodic timer repaints without starting a vsync ticker. tick counts
    // missed intervals, so a slow frame does not slow the animation down.
    final base = _ticks;
    _timer = Timer.periodic(interval, (timer) {
      _ticks = base + timer.tick;
      notifyListeners();
    });
  }

  void detach() {
    assert(_clients > 0);
    _clients--;
    if (_clients == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Attaches the owning [State] to [StatusAnimationClock] while it animates and
/// tickers are enabled, e.g. not on an offstage route.
///
/// Painters should take `repaint: statusClockAttached ? clock : null` so a
/// tick only repaints, never rebuilds.
mixin StatusAnimationClockMixin<T extends StatefulWidget> on State<T> {
  bool _attached = false;

  /// Override to pause the loop, e.g. when a fixed value is shown.
  bool get animatesStatus => true;

  bool get statusClockAttached => _attached;

  StatusAnimationClock get statusClock => StatusAnimationClock.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncStatusClock();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStatusClock();
  }

  void _syncStatusClock() {
    final attach = animatesStatus && TickerMode.valuesOf(context).enabled;
    if (attach == _attached) {
      return;
    }
    _attached = attach;
    if (attach) {
      statusClock.attach();
    } else {
      statusClock.detach();
    }
  }

  @override
  void dispose() {
    if (_attached) {
      statusClock.detach();
      _attached = false;
    }
    super.dispose();
  }
}
