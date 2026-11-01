// 职责: 订阅 a2ui_core 的 signal，在其变化时只重建当前 Widget。
// 关联文件:
//   lib/shared/widgets/a2ui/node_view.dart
//   lib/shared/widgets/a2ui/surface_view.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 订阅 [signal]，值变化时重建调用方；返回当前值。
///
/// 输入框写回数据时 signal 可能在 build/layout 阶段同步变化，此时把重建推迟到帧末。
T useSignal<T>(ReadonlySignal<T> signal) {
  final context = useContext();
  useEffect(() {
    var primed = false;
    // subscribe 会立即同步回调一次当前值，跳过这一次。
    final unsubscribe = signal.subscribe((_) {
      if (!primed) {
        return;
      }
      _markNeedsBuild(context);
    });
    primed = true;
    return unsubscribe;
  }, [signal]);
  return signal.peek();
}

void _markNeedsBuild(BuildContext context) {
  if (!context.mounted) {
    return;
  }
  final scheduler = SchedulerBinding.instance;
  if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    scheduler.addPostFrameCallback((_) {
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    });
    return;
  }
  (context as Element).markNeedsBuild();
}
