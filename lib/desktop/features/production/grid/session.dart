// 职责: 将宫格切分规格和选中格保存在所选节点的局部会话中，并处理 Esc 退出。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/grid/split_overlay.dart
//   lib/desktop/features/production/grid/split_bar.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

typedef GridSpec = ({int rows, int cols});

class GridSplitSession extends ChangeNotifier {
  GridSplitSession(this.nodeId);
  final String? nodeId;
  GridSpec? spec;
  Set<int> selected = {};
  bool get active => spec != null;
  void start(GridSpec value) {
    spec = value;
    selected = {};
    notifyListeners();
  }

  void toggle(int index) {
    selected = {...selected};
    if (!selected.remove(index)) {
      selected.add(index);
    }
    notifyListeners();
  }

  void close() {
    spec = null;
    selected = {};
    notifyListeners();
  }
}

class ProductionGridWorkspace extends HookWidget {
  const ProductionGridWorkspace({
    super.key,
    required this.nodeId,
    required this.child,
  });
  final String? nodeId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final session = useMemoized(() => GridSplitSession(nodeId), [nodeId]);
    useEffect(() {
      bool onKey(KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            session.active) {
          session.close();
          return true;
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(onKey);
      return () {
        HardwareKeyboard.instance.removeHandler(onKey);
        session.dispose();
      };
    }, [session]);
    return ProductionGridSession(notifier: session, child: child);
  }
}

class ProductionGridSession extends InheritedNotifier<GridSplitSession> {
  const ProductionGridSession({
    super.key,
    required super.notifier,
    required super.child,
  });
  static GridSplitSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProductionGridSession>()
      ?.notifier;
}
