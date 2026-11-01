// 职责: 桌面端统一处理 Cmd/Ctrl+S，并串行调用当前编辑上下文的保存回调。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/home.dart
//   test/desktop/widgets/desktop_save_shortcut_test.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DesktopSaveIntent extends Intent {
  const DesktopSaveIntent();
}

class DesktopSaveShortcut extends StatefulWidget {
  const DesktopSaveShortcut({
    super.key,
    required this.onSave,
    required this.child,
  });

  final Future<void> Function() onSave;
  final Widget child;

  @override
  State<DesktopSaveShortcut> createState() => _DesktopSaveShortcutState();
}

class _DesktopSaveShortcutState extends State<DesktopSaveShortcut> {
  bool _saveInFlight = false;

  void _invokeSave() {
    if (_saveInFlight) {
      return;
    }
    _saveInFlight = true;
    _runSave();
  }

  Future<void> _runSave() async {
    try {
      await widget.onSave();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'desktop save shortcut',
          context: ErrorDescription('while invoking Cmd/Ctrl+S'),
        ),
      );
    } finally {
      _saveInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            DesktopSaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            DesktopSaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DesktopSaveIntent: CallbackAction<DesktopSaveIntent>(
            onInvoke: (_) {
              _invokeSave();
              return null;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }
}
