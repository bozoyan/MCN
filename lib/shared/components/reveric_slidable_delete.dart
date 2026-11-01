// 职责: 通用左滑删除容器 — 展示删除操作并让内容卡片随滑动调整右侧圆角。
// 关联文件:
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../theme/theme.dart';

/// 构建左滑删除内容。打开删除操作时，[borderRadius] 的右侧圆角会被拉直。
typedef RevericSlidableDeleteChildBuilder =
    Widget Function(BuildContext context, BorderRadius borderRadius);

/// 移动端列表通用左滑删除操作。
///
/// 调用方负责确认与持久化删除；组件只负责手势、删除操作面板和圆角过渡。
class RevericSlidableDelete extends StatefulWidget {
  const RevericSlidableDelete({
    super.key,
    required this.childBuilder,
    required this.onDelete,
    required this.deleteLabel,
    required this.borderRadius,
    this.actionExtentRatio = 0.26,
  }) : assert(actionExtentRatio > 0);

  final RevericSlidableDeleteChildBuilder childBuilder;
  final FutureOr<void> Function() onDelete;
  final String deleteLabel;
  final BorderRadius borderRadius;
  final double actionExtentRatio;

  @override
  State<RevericSlidableDelete> createState() => _RevericSlidableDeleteState();
}

class _RevericSlidableDeleteState extends State<RevericSlidableDelete>
    with TickerProviderStateMixin {
  late final SlidableController _controller = SlidableController(this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Slidable(
        controller: _controller,
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: widget.actionExtentRatio,
          children: [
            CustomSlidableAction(
              onPressed: (_) {
                final result = widget.onDelete();
                if (result is Future<void>) {
                  unawaited(result);
                }
              },
              backgroundColor: colors.error.withValues(alpha: 0.88),
              borderRadius: BorderRadius.zero,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIcon(
                    RevericIcons.delete_outline,
                    size: 20,
                    color: colors.onAccent,
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    widget.deleteLabel,
                    style: typo.uiTiny.copyWith(color: colors.onAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _controller.animation,
          builder: (context, _) {
            final open = (-_controller.ratio / widget.actionExtentRatio)
                .clamp(0.0, 1.0)
                .toDouble();
            return widget.childBuilder(context, _openBorderRadius(open));
          },
        ),
      ),
    );
  }

  BorderRadius _openBorderRadius(double open) {
    Radius flattenRight(Radius radius) =>
        Radius.elliptical(radius.x * (1 - open), radius.y * (1 - open));

    return BorderRadius.only(
      topLeft: widget.borderRadius.topLeft,
      bottomLeft: widget.borderRadius.bottomLeft,
      topRight: flattenRight(widget.borderRadius.topRight),
      bottomRight: flattenRight(widget.borderRadius.bottomRight),
    );
  }
}
