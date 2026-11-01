// 职责: 画布边类型选择列表与线型色板 — 落点弹层与连线原地编辑共用的选择控件
// 关联文件:
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../canvas_palette.dart';
import 'canvas_node_widget.dart';

/// 边类型的线型色板：用一小段线预览该类型的颜色与虚实,
/// 让「选类型」这件事在视觉上直接对应画布上看到的那条线。
class CanvasEdgeTypeSwatch extends StatelessWidget {
  const CanvasEdgeTypeSwatch({super.key, required this.type, this.width = 26});

  final String type;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return SizedBox(
      width: width,
      height: 2,
      child: CustomPaint(
        painter: _EdgeSwatchPainter(
          color: canvasEdgeColor(colors, type),
          dashPattern: canvasEdgeDashPattern(type),
        ),
      ),
    );
  }
}

class _EdgeSwatchPainter extends CustomPainter {
  const _EdgeSwatchPainter({required this.color, required this.dashPattern});

  final Color color;
  final List<double>? dashPattern;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final pattern = dashPattern;
    if (pattern == null || pattern.isEmpty) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var index = 0;
    var drawing = true;
    while (x < size.width) {
      final segment = pattern[index % pattern.length];
      final end = (x + segment).clamp(0.0, size.width);
      if (drawing) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      }
      x = end;
      index += 1;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(_EdgeSwatchPainter oldDelegate) {
    return color != oldDelegate.color || dashPattern != oldDelegate.dashPattern;
  }
}

/// 边类型选择列表：5 行(线型预览 + 标签 + 说明 + 选中勾)。
///
/// 落点弹层与连线原地编辑共用；[compact] 为 true 时隐藏说明文字。
class CanvasEdgeTypeList extends StatelessWidget {
  const CanvasEdgeTypeList({
    super.key,
    required this.value,
    required this.onPick,
    this.compact = false,
  });

  /// 当前选中的类型；新建连线时为 null。
  final String? value;
  final ValueChanged<String> onPick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final type in canvasEdgeTypes)
          _EdgeTypeRow(
            type: type,
            isActive: value == type,
            compact: compact,
            colors: colors,
            typo: typo,
            onTap: () => onPick(type),
          ),
      ],
    );
  }
}

class _EdgeTypeRow extends StatelessWidget {
  const _EdgeTypeRow({
    required this.type,
    required this.isActive,
    required this.compact,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String type;
  final bool isActive;
  final bool compact;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      hoverColor: colors.hover,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? colors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(
            color: isActive
                ? colors.accent.withValues(alpha: 0.30)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            CanvasEdgeTypeSwatch(type: type),
            const SizedBox(width: RevericSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    canvasEdgeTypeLabel(context, type),
                    style: typo.uiSmallSemibold.copyWith(
                      color: isActive
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  if (!compact)
                    Text(
                      canvasEdgeTypeDescription(context, type),
                      style: typo.uiTiny.copyWith(color: colors.textSubtle),
                    ),
                ],
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: RevericSpacing.xs),
              RevericIcon(
                RevericIcons.check,
                size: 13,
                color: colors.accentWarm,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 连线落点后的类型选择卡：拖出连线松手时弹出,选定类型才真正落库。
///
/// 不给默认类型——「这条线是什么关系」是作者的判断,静默写一个泛化类型会让
/// 画布上很快堆满无意义的关联线。
class CanvasEdgeTypePickerCard extends StatelessWidget {
  const CanvasEdgeTypePickerCard({
    super.key,
    required this.onPick,
    required this.onCancel,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  /// 卡片宽度(定位时需要,用于水平居中于落点)。
  static const double width = 244;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return CanvasFloatingCard(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.md,
              RevericSpacing.sm,
              RevericSpacing.sm,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.link,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.canvasEdgeTypePrompt),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                CanvasIconButton(
                  icon: RevericIcons.close,
                  tooltip: context.t(LocaleKeys.commonCancel),
                  onTap: onCancel,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(RevericSpacing.xs),
            child: CanvasEdgeTypeList(
              value: null,
              onPick: onPick,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// 浮在画布上的卡片外壳(选择器/详情面板共用的描边与投影)。
class CanvasFloatingCard extends StatelessWidget {
  const CanvasFloatingCard({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.38 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// 画布浮层里的小图标按钮。
class CanvasIconButton extends StatelessWidget {
  const CanvasIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        hoverColor: colors.hover,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: RevericIcon(
              icon,
              size: 14,
              color: danger ? colors.deletionBorder : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
