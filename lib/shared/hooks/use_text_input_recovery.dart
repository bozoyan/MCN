// 职责: 桌面端文本输入连接恢复 — 窗口重获焦点时强制重连 IME，绕过 embedder 静默失效
// 关联文件:
//   lib/shared/utils/text_input_composing.dart
//   lib/desktop/widgets/ai/chat/composer.dart
//   lib/desktop/widgets/ai/chat/panel.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md

import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/text_input_composing.dart';

bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// 桌面端：窗口重新获得焦点时强制重建文本输入连接，恢复被卡死的输入法。
///
/// macOS embedder 的 `FlutterTextInputPlugin` 在 `show` 分支里对 nil view
/// controller 执行 `addSubview`、对 nil window 执行 `makeFirstResponder`，两者都
/// 静默失败（唯一的 `FML_DCHECK` 在 release 构建被编译掉），却仍把 `_shown` 置为
/// TRUE。Dart 侧 `EditableText._hasInputConnection` 同样认为连接健在，于是**永远不会
/// 再发 `show`** —— 用户表现为「突然打不了中文，切到别的软件正常，切回来还是不行」。
///
/// 恢复手法：走一次 `unfocus()` → 下一帧 `requestFocus()`，逼 embedder 重新执行
/// `setClient`（重新按 viewId 解析 view controller）+ `show`（重新挂回 view
/// hierarchy 并重新 `makeFirstResponder`）。
///
/// **这是缓解不是根因修复**：Dart 侧无法探测「已卡死」状态（框架认为一切正常），只能
/// 在安全时机机会性重连。组词期间一律跳过，否则恢复动作本身会丢掉正在输入的拼音。
///
/// 移动端不注册：那里 `unfocus`/`requestFocus` 会收起再弹出软键盘，纯打扰。
void useTextInputConnectionRecovery({
  required FocusNode focusNode,
  required TextEditingController controller,
}) {
  // 转发成稳定 ref，避免把每帧可能换实例的入参写进 effect keys。
  final focusNodeRef = useRef(focusNode);
  final controllerRef = useRef(controller);
  focusNodeRef.value = focusNode;
  controllerRef.value = controller;

  final reattach = useCallback(() {
    if (!_isDesktopPlatform) {
      return;
    }
    final node = focusNodeRef.value;
    // 没焦点时不抢焦点；组词期间重连会丢掉正在输入的拼音。
    if (!node.hasFocus || isTextInputComposing(controllerRef.value)) {
      return;
    }
    node.unfocus();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.canRequestFocus) {
        node.requestFocus();
      }
    });
  }, const []);

  useEffect(() {
    if (!_isDesktopPlatform) {
      return null;
    }
    final listener = _TextInputRecoveryListener(reattach);
    windowManager.addListener(listener);
    return () => windowManager.removeListener(listener);
  }, [reattach]);

  // 窗口事件之外再兜一层：部分平台/场景只走 app 生命周期。
  useOnAppLifecycleStateChange((previous, current) {
    if (current == AppLifecycleState.resumed) {
      reattach();
    }
  });
}

class _TextInputRecoveryListener extends WindowListener {
  _TextInputRecoveryListener(this._onFocusRegained);

  final VoidCallback _onFocusRegained;

  @override
  void onWindowFocus() {
    _onFocusRegained();
  }
}
