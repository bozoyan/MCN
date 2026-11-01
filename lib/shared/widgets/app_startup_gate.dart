// 职责: 首帧展示启动占位，执行一次初始化，成功或失败后才挂载业务子树。
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../logger/app_logger.dart';

final _log = AppLogger.forModule('Startup');

class AppStartupGate extends HookWidget {
  const AppStartupGate({
    super.key,
    required this.initialize,
    required this.loading,
    required this.child,
  });

  final Future<void> Function() initialize;
  final Widget loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final initialization = useMemoized(() async {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) {
        return;
      }
      try {
        await initialize();
      } catch (error, stackTrace) {
        _log.error(
          'App initialization tasks failed, continuing startup',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }, const []);
    final result = useFuture(initialization);
    return result.connectionState == ConnectionState.done ? child : loading;
  }
}
