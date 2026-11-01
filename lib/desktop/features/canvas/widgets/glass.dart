// 职责: 画布悬浮控件的毛玻璃表面与画布动效节奏，构思画布和制作画布共用。
// 关联文件:
//   lib/shared/theme/canvas_colors.dart
//   lib/desktop/features/canvas/widgets/floating_cluster.dart
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/canvas_controls.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../shared/theme/canvas_colors.dart';
import '../../../../shared/theme/theme.dart';

/// 画布交互的动效节奏。所有过渡都是一次性的，结束即停，不做循环动画。
abstract final class CanvasMotion {
  /// 端口、小图标这类小元素的出现。
  static const fast = Duration(milliseconds: 120);

  /// 卡片悬停、选中的底色与描边。
  static const hover = Duration(milliseconds: 150);

  /// 浮层（工具条、输入框）进场。
  static const enter = Duration(milliseconds: 180);

  static const curve = Curves.easeOutCubic;
}

/// 浮在画布上的毛玻璃表面：半透明底、发丝描边、大而淡的投影。
///
/// 模糊只用在少量悬浮控件上；节点卡数量多，不走这里，见 `canvasGlassFill`。
class CanvasGlass extends StatelessWidget {
  const CanvasGlass({
    super.key,
    required this.child,
    this.radius = RevericRadius.capsule,
    this.padding = EdgeInsets.zero,
    this.raised = false,
    this.circle = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 承载输入的浮层更实一些，正文对比度不受底下内容影响。
  final bool raised;

  /// 圆形（添加按钮外圈）；为 true 时忽略 [radius]。
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final border = Border.all(color: canvasGlassBorder(colors));
    final borderRadius = circle ? null : BorderRadius.circular(radius);
    final shape = circle ? BoxShape.circle : BoxShape.rectangle;
    final surface = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: canvasGlassFill(colors, raised: raised),
          shape: shape,
          borderRadius: borderRadius,
          border: border,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: borderRadius,
        boxShadow: canvasGlassShadows(colors),
      ),
      // 模糊必须裁在自身形状内，否则会糊掉整块背景。
      child: circle
          ? ClipOval(child: surface)
          : ClipRRect(borderRadius: borderRadius!, child: surface),
    );
  }
}

/// 浮层进场：淡入并从锚点方向滑入一小段；[slideFrom] 为相对自身尺寸的起始偏移。
///
/// 换 key 会重新进场，比如选中另一个节点时。
class CanvasEnter extends StatefulWidget {
  const CanvasEnter({
    super.key,
    required this.child,
    this.slideFrom = const Offset(0, .04),
  });

  final Widget child;
  final Offset slideFrom;

  @override
  State<CanvasEnter> createState() => _CanvasEnterState();
}

class _CanvasEnterState extends State<CanvasEnter>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: CanvasMotion.enter,
  )..forward();
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: CanvasMotion.curve,
  );
  late final _slide = Tween(
    begin: widget.slideFrom,
    end: Offset.zero,
  ).animate(_curve);

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
