// 职责: 展示风格缩略图，按预设 slug 加载内置预览图片，其余状态使用图标。
// 关联文件:
//   lib/desktop/features/production/style_picker.dart
//   lib/desktop/features/production/style_button.dart
//   lib/shared/models/production/style.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/theme/theme.dart';

enum ProductionStyleThumbKind { none, preset, custom, create, missing }

/// 风格在界面上的样子：名称 + 缩略图。[seed] 是预设 slug，对应内置预览图的文件名。
typedef ProductionStyleLook = ({
  String label,
  ProductionStyleThumbKind kind,
  String seed,
});

class ProductionStyleThumb extends StatelessWidget {
  const ProductionStyleThumb({
    super.key,
    required this.kind,
    this.seed = '',
    this.size,
    this.radius = 0,
    this.iconSize,
  });

  final ProductionStyleThumbKind kind;
  final String seed;

  /// null 时铺满父级（风格卡片的预览区）。
  final double? size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final borderRadius = BorderRadius.circular(radius);
    final Widget body;
    if (kind == ProductionStyleThumbKind.preset) {
      body = _PresetArt(seed: seed);
    } else {
      final icon = switch (kind) {
        ProductionStyleThumbKind.custom => RevericIcons.palette_outlined,
        ProductionStyleThumbKind.create => RevericIcons.pencil_simple,
        _ => RevericIcons.block_outlined,
      };
      body = ColoredBox(
        color: kind == ProductionStyleThumbKind.custom
            ? colors.selected
            : colors.surfaceContainerHigh,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: RevericIcon(
              icon,
              size:
                  iconSize ??
                  (constraints.biggest.shortestSide * .6).roundToDouble(),
              color: kind == ProductionStyleThumbKind.custom
                  ? colors.accentWarm
                  : colors.textMuted,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: borderRadius, child: body),
    );
  }
}

/// 根据显示区域和屏幕像素密度解码预览，避免小尺寸按钮加载完整图片。
class _PresetArt extends StatelessWidget {
  const _PresetArt({required this.seed});
  final String seed;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 原图为 384×216；方形按钮使用 cover 时，以高度计算足够的解码宽度。
        final width = math.max(
          constraints.maxWidth,
          constraints.maxHeight * 16 / 9,
        );
        return Image.asset(
          'assets/images/production_styles/$seed.webp',
          fit: BoxFit.cover,
          cacheWidth: (width * pixelRatio).ceil().clamp(1, 384),
          excludeFromSemantics: true,
        );
      },
    );
  }
}
