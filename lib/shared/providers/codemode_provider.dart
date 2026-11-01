// 职责: 为同一应用容器提供一个跨会话共享的轻量 Codemode 名额调度器。
// 关联文件:
//   lib/shared/services/ai/codemode/scheduler.dart
//   lib/shared/services/ai/chat_turn_runner.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/ai/codemode/scheduler.dart';

part 'codemode_provider.g.dart';

// One bounded queue per app container, retained across page/session switches.
// Engine instances and script data are never retained by this provider.
@Riverpod(keepAlive: true)
CodemodeScheduler codemodeScheduler(Ref ref) {
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final scheduler = CodemodeScheduler(maxActive: mobile ? 1 : 2);
  ref.onDispose(scheduler.dispose);
  return scheduler;
}
