// 职责: 在切分图片上显示等分网格、选中高亮与行列标签。
// 关联文件:
//   lib/desktop/features/production/grid/session.dart
//   lib/desktop/features/production/node_card.dart
import 'package:flutter/material.dart';
import '../../../../shared/theme/theme.dart';
import '../support.dart';
import 'session.dart';

class ProductionGridOverlay extends StatelessWidget {
  const ProductionGridOverlay({
    super.key,
    required this.nodeId,
    required this.child,
  });
  final String nodeId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final session = ProductionGridSession.maybeOf(context);
    final spec = session?.nodeId == nodeId ? session?.spec : null;
    if (spec == null) {
      return child;
    }
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final divider = BorderSide(
      color: colors.accent.withValues(alpha: .75),
      width: 1,
    );
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: Column(
            children: [
              for (var row = 0; row < spec.rows; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < spec.cols; col++)
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('grid-cell/$row/$col'),
                            supportedDevices: productionPointerDragDevices,
                            behavior: HitTestBehavior.opaque,
                            onTap: () => session.toggle(row * spec.cols + col),
                            onPanUpdate: (_) {},
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    session!.selected.contains(
                                      row * spec.cols + col,
                                    )
                                    ? colors.accent.withValues(alpha: .25)
                                    : null,
                                // 只画格与格之间的细线，图片外沿不描边，相邻两格不叠成双线。
                                border: Border(
                                  right: col < spec.cols - 1
                                      ? divider
                                      : BorderSide.none,
                                  bottom: row < spec.rows - 1
                                      ? divider
                                      : BorderSide.none,
                                ),
                              ),
                              child:
                                  session.selected.contains(
                                    row * spec.cols + col,
                                  )
                                  ? Center(
                                      child: Text(
                                        '${row + 1}-${col + 1}',
                                        style: typo.uiSemibold.copyWith(
                                          color: colors.onAccent,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
