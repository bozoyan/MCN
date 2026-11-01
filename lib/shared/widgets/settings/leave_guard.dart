// 职责: 让设置弹窗在切换分区或关闭前，询问正在编辑的区域是否可以离开。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/mcp/server_editor.dart
import 'package:flutter/widgets.dart';

/// 返回 false 表示留在当前编辑处。
typedef SettingsLeaveGuard = Future<bool> Function();

/// 同一时刻只有一个分区可见，因此只保留最后登记的守卫。
class SettingsLeaveController {
  SettingsLeaveGuard? _guard;

  void register(SettingsLeaveGuard guard) {
    _guard = guard;
  }

  void unregister(SettingsLeaveGuard guard) {
    if (identical(_guard, guard)) {
      _guard = null;
    }
  }

  Future<bool> confirmLeave() async {
    final guard = _guard;
    return guard == null || await guard();
  }
}

class SettingsLeaveScope extends InheritedWidget {
  const SettingsLeaveScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SettingsLeaveController controller;

  /// 不建立依赖：控制器在设置弹窗生命周期内不变。
  static SettingsLeaveController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsLeaveScope>()?.controller;

  @override
  bool updateShouldNotify(SettingsLeaveScope oldWidget) =>
      controller != oldWidget.controller;
}
