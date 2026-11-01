// 职责: 共享插件与 Codemode 的 fjs 原生库单次初始化。
// 关联文件:
//   lib/shared/services/plugins/runtime.dart
//   lib/shared/services/ai/codemode/runtime.dart
import 'package:fjs/fjs.dart';

Future<void>? _initialization;
Future<void> initializeJavascript() {
  if (_initialization != null) {
    return _initialization!;
  }
  // 外部原生宿主或测试可以在进入应用执行器前加载平台库。
  // ignore: invalid_use_of_internal_member
  if (LibFjs.instance.initialized) {
    return Future<void>.value();
  }
  return _initialization ??= LibFjs.init();
}
