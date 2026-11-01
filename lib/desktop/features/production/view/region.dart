// 职责: 管理所选节点的派生面板会话，并在节点下方替换编辑区。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/view/panel.dart
//   lib/desktop/features/production/view/actions.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/models/production/view_presets.dart';
import '../../../../shared/services/production/canvas_service.dart';
import 'panel.dart';

class ProductionViewWorkspace extends HookWidget {
  const ProductionViewWorkspace({
    super.key,
    required this.nodeId,
    required this.child,
  });
  final String? nodeId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final selected = useState<ViewPreset?>(null);
    useEffect(() {
      selected.value = null;
      return null;
    }, [nodeId]);
    return ProductionViewSession(notifier: selected, child: child);
  }
}

class ProductionViewSession
    extends InheritedNotifier<ValueNotifier<ViewPreset?>> {
  const ProductionViewSession({
    super.key,
    required super.notifier,
    required super.child,
  });
  static ValueNotifier<ViewPreset?> of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProductionViewSession>()!
      .notifier!;
}

class ProductionViewComposer extends StatelessWidget {
  const ProductionViewComposer({
    super.key,
    required this.service,
    required this.node,
    this.child,
  });
  final ProductionCanvasService service;
  final CanvasNode node;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final session = ProductionViewSession.of(context);
    final preset = session.value;
    // Stack 把外层的高度上限传给面板，放不下时面板内部滚动；
    // 隐藏的输入框保留编辑状态，离屏时不占尺寸。
    return Stack(
      children: [
        Offstage(
          offstage: preset != null,
          child: child ?? const SizedBox.shrink(),
        ),
        if (preset != null)
          ProductionViewPanel(
            key: ValueKey('${node.id}/${preset.name}'),
            service: service,
            node: node,
            preset: preset,
            onClose: () => session.value = null,
          ),
      ],
    );
  }
}

/// 让画布浮层读取数据库投影中的最新节点，而不是最初选中的快照。
class ProductionViewNode extends InheritedWidget {
  const ProductionViewNode({
    super.key,
    required this.node,
    required super.child,
  });
  final CanvasNode node;
  static CanvasNode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProductionViewNode>()?.node;
  @override
  bool updateShouldNotify(ProductionViewNode old) => old.node != node;
}
