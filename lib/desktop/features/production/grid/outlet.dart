// 职责: 将分镜组的成员连线汇聚到共同出口，统一创建参考草稿或拖向已有节点。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/grid/group_node.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/components/reveric_icon_button.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/production/group_layout.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../third/flow/vyuh_node_flow.dart' as flow;
import '../support.dart';
import 'group_node.dart';

class ProductionGroupOutlet extends StatelessWidget {
  const ProductionGroupOutlet({
    super.key,
    required this.controller,
    required this.onConnect,
    this.onCreate,
  });
  final flow.NodeFlowController<String, String> controller;
  final void Function(String groupId, String targetId, Offset at) onConnect;
  final void Function(String groupId, bool video, Offset at)? onCreate;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final selected = controller.selectedNodeIds;
      final groups = controller.nodes.values
          .whereType<ProductionFlowGroup>()
          .where(
            (g) =>
                g.layout is StoryboardGroupLayout &&
                g.nodeIds.isNotEmpty &&
                (selected.contains(g.id) || g.nodeIds.any(selected.contains)),
          )
          .toList();
      if (groups.length != 1) {
        return const SizedBox.shrink();
      }
      return _Outlet(
        key: ValueKey(groups.single.id),
        group: groups.single,
        controller: controller,
        onConnect: onConnect,
        onCreate: onCreate,
      );
    },
  );
}

class _Outlet extends HookWidget {
  const _Outlet({
    super.key,
    required this.group,
    required this.controller,
    required this.onConnect,
    this.onCreate,
  });
  final ProductionFlowGroup group;
  final flow.NodeFlowController<String, String> controller;
  final void Function(String, String, Offset) onConnect;
  final void Function(String, bool, Offset)? onCreate;

  @override
  Widget build(BuildContext context) {
    final endpoint = useState<Offset?>(null);
    final dragging = useRef(false);
    final colors = RevericTheme.colorsOf(context);
    Offset local(Offset global) =>
        (context.findRenderObject()! as RenderBox).globalToLocal(global);
    Offset global(Offset at) =>
        (context.findRenderObject()! as RenderBox).localToGlobal(at);
    Offset graph(Offset at) =>
        controller.screenToGraph(flow.ScreenPosition(at)).offset;
    Future<void> menu(Offset at) async {
      endpoint.value = at;
      try {
        await showRevericContextMenu(
          context: context,
          position: global(at),
          entries: [
            RevericMenuItem(
              label: context.t(
                LocaleKeys.productionGroupReferenceCount,
                namedArgs: {'count': '${group.nodeIds.length}'},
              ),
              enabled: false,
            ),
            const RevericMenuDivider(),
            RevericMenuItem(
              label: context.t(LocaleKeys.productionGroupReferenceImage),
              icon: RevericIcons.image,
              enabled: onCreate != null,
              onTap: () => onCreate?.call(group.id, false, graph(at)),
            ),
            RevericMenuItem(
              label: context.t(LocaleKeys.productionGroupReferenceVideo),
              icon: RevericIcons.movie_outlined,
              enabled: onCreate != null,
              onTap: () => onCreate?.call(group.id, true, graph(at)),
            ),
          ],
        );
      } finally {
        if (context.mounted) {
          endpoint.value = null;
        }
      }
    }

    return Observer(
      builder: (_) {
        final viewport = controller.viewportObservable.value;
        Offset screen(Offset at) =>
            viewport.toScreen(flow.GraphPosition(at)).offset;
        final outlet =
            screen((group.position.value & group.size.value).centerRight) +
            const Offset(RevericSpacing.x4l, 0);
        final end = endpoint.value ?? outlet;
        final slots = group.slots.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final starts = [
          for (final entry in slots)
            if (controller.getNode(entry.value) case final node?)
              screen((node.position.value & node.size.value).centerRight),
        ];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: ValueKey('group-fan/${group.id}'),
                  painter: _Fan(
                    starts,
                    end,
                    colors.textMuted,
                    Rect.fromPoints(
                      screen(group.position.value),
                      screen(
                        group.position.value +
                            group.size.value.bottomRight(Offset.zero),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: end.dx - RevericSpacing.x2l,
              top: end.dy - RevericSpacing.x2l,
              child: Listener(
                onPointerCancel: (_) {
                  dragging.value = false;
                  endpoint.value = null;
                },
                child: GestureDetector(
                  key: ValueKey('group-outlet/${group.id}'),
                  supportedDevices: productionPointerDragDevices,
                  onPanStart: (d) {
                    dragging.value = true;
                    endpoint.value = local(d.globalPosition);
                  },
                  onPanUpdate: (d) => endpoint.value = local(d.globalPosition),
                  onPanCancel: () {
                    dragging.value = false;
                    endpoint.value = null;
                  },
                  onPanEnd: (_) {
                    if (!dragging.value) {
                      return;
                    }
                    dragging.value = false;
                    final at = endpoint.value ?? outlet;
                    final point = graph(at);
                    if ((group.position.value & group.size.value).contains(
                      point,
                    )) {
                      endpoint.value = null;
                      return;
                    }
                    final target = controller.nodes.values
                        .where(
                          (n) =>
                              n is! ProductionFlowGroup &&
                              !group.nodeIds.contains(n.id) &&
                              (n.position.value & n.size.value).contains(point),
                        )
                        .firstOrNull;
                    if (target != null) {
                      endpoint.value = null;
                      onConnect(group.id, target.id, global(at));
                    } else {
                      menu(at);
                    }
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surfaceContainerHigh,
                      border: Border.all(color: colors.border),
                    ),
                    child: RevericIconButton(
                      icon: RevericIcons.add,
                      tooltip: context.t(
                        LocaleKeys.productionGroupReferenceCount,
                        namedArgs: {'count': '${group.nodeIds.length}'},
                      ),
                      onPressed: () => menu(outlet),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Fan extends CustomPainter {
  const _Fan(this.starts, this.end, this.color, this.frame);
  final Rect frame;
  final List<Offset> starts;
  final Offset end;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(frame),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final start in starts) {
      final bend = (end.dx - start.dx).abs() * .5;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + bend,
            start.dy,
            end.dx - bend,
            end.dy,
            end.dx,
            end.dy,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Fan old) =>
      old.frame != frame ||
      old.end != end ||
      old.color != color ||
      old.starts.length != starts.length ||
      List.generate(
        starts.length,
        (i) => i,
      ).any((i) => old.starts[i] != starts[i]);
}
