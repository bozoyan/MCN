// 职责: A2UI 布局组件 Row、Column、List、Gap 的 builder。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/components/horizontal_wheel_scroll.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../components/horizontal_wheel_scroll.dart';
import '../../../theme/theme.dart';
import '../component.dart';

const double _columnGap = RevericSpacing.lg;
const double _rowGap = RevericSpacing.sm;

/// 自身宽度固定、在 Row 中不参与均分剩余宽度的组件。
const _intrinsicWidthTypes = {'Icon', 'Button', 'Loading', 'Gap', 'Divider'};

/// 只由这些组件组成的 Row 是按钮栏，宽度不够时换行而不是溢出。
const _wrappableTypes = {'Icon', 'Button'};

Widget buildColumn(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) => _flex(Axis.vertical, props, buildChild);

Widget buildRow(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) => _flex(Axis.horizontal, props, buildChild);

/// 有界时按需构建子项（数据模板生成的长列表），无界时退回普通排版，
/// 由外层滚动容器负责滚动，避免嵌套无界视口。
Widget buildList(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final direction = props.string('direction') == 'horizontal'
      ? Axis.horizontal
      : Axis.vertical;
  final children = props.children('children');
  final align = props.string('align');
  return LayoutBuilder(
    builder: (context, constraints) {
      final vertical = direction == Axis.vertical;
      final mainBounded = vertical
          ? constraints.hasBoundedHeight
          : constraints.hasBoundedWidth;
      final crossBounded = vertical
          ? constraints.hasBoundedWidth
          : constraints.hasBoundedHeight;
      if (vertical && !mainBounded) {
        return _flex(direction, props, buildChild);
      }
      if (!vertical && !(mainBounded && crossBounded)) {
        // 横向视口需要有界高度；高度无界时整行排版并横向滚动。
        return HorizontalWheelScroll(
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            primary: false,
            child: _flex(direction, props, buildChild),
          ),
        );
      }
      Widget item(BuildContext context, int index) {
        final child = buildChild(children[index]);
        if (align == null || align == 'stretch') {
          return child;
        }
        return Align(
          alignment: vertical
              ? _crossAlignment(align, horizontal: true)
              : _crossAlignment(align, horizontal: false),
          widthFactor: vertical ? null : 1,
          heightFactor: vertical ? 1 : null,
          child: child,
        );
      }

      Widget separator(BuildContext context, int index) => SizedBox(
        width: vertical ? 0 : _rowGap,
        height: vertical ? _columnGap : 0,
      );

      if (vertical) {
        return ListView.separated(
          primary: false,
          itemCount: children.length,
          itemBuilder: item,
          separatorBuilder: separator,
        );
      }
      return HorizontalWheelScroll(
        builder: (context, controller) => ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          itemBuilder: item,
          separatorBuilder: separator,
        ),
      );
    },
  );
}

const _gapSizes = {
  'xs': RevericSpacing.xxs,
  'sm': RevericSpacing.sm,
  'md': RevericSpacing.lg,
  'lg': RevericSpacing.x2l,
  'xl': RevericSpacing.x4l,
};

Widget buildGap(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final size = _gapSizes[props.string('size')] ?? _gapSizes['md']!;
  return SizedBox.square(dimension: size);
}

AlignmentDirectional _crossAlignment(String align, {required bool horizontal}) {
  return switch ((align, horizontal)) {
    ('center', _) => AlignmentDirectional.center,
    ('end', true) => AlignmentDirectional.centerEnd,
    ('end', false) => AlignmentDirectional.bottomCenter,
    (_, true) => AlignmentDirectional.centerStart,
    (_, false) => AlignmentDirectional.topCenter,
  };
}

MainAxisAlignment _justifyOf(String? justify) => switch (justify) {
  'center' => MainAxisAlignment.center,
  'end' => MainAxisAlignment.end,
  'spaceBetween' => MainAxisAlignment.spaceBetween,
  'spaceAround' => MainAxisAlignment.spaceAround,
  'spaceEvenly' => MainAxisAlignment.spaceEvenly,
  _ => MainAxisAlignment.start,
};

CrossAxisAlignment _alignOf(String? align) => switch (align) {
  'start' => CrossAxisAlignment.start,
  'center' => CrossAxisAlignment.center,
  'end' => CrossAxisAlignment.end,
  _ => CrossAxisAlignment.stretch,
};

WrapAlignment _wrapAlignmentOf(MainAxisAlignment justify) => switch (justify) {
  MainAxisAlignment.center => WrapAlignment.center,
  MainAxisAlignment.end => WrapAlignment.end,
  MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
  MainAxisAlignment.spaceAround => WrapAlignment.spaceAround,
  MainAxisAlignment.spaceEvenly => WrapAlignment.spaceEvenly,
  _ => WrapAlignment.start,
};

WrapCrossAlignment _wrapCrossAlignmentOf(CrossAxisAlignment align) =>
    switch (align) {
      CrossAxisAlignment.center => WrapCrossAlignment.center,
      CrossAxisAlignment.end => WrapCrossAlignment.end,
      _ => WrapCrossAlignment.start,
    };

/// A2UI 的 `weight` 允许小数，换算为 Flutter 的整数 flex。
int _flexOf(A2uiNode child) {
  final weight = A2uiProps(child.props.peek()).number('weight') ?? 0;
  return weight > 0 ? math.max(1, (math.min(weight, 10000) * 100).round()) : 0;
}

Widget _flex(Axis direction, A2uiProps props, A2uiChildBuilder buildChild) {
  final children = props.children('children');
  final justify = _justifyOf(props.string('justify'));
  final align = _alignOf(props.string('align'));
  final horizontal = direction == Axis.horizontal;
  return LayoutBuilder(
    builder: (context, constraints) {
      final mainBounded = horizontal
          ? constraints.hasBoundedWidth
          : constraints.hasBoundedHeight;
      final crossBounded = horizontal
          ? constraints.hasBoundedHeight
          : constraints.hasBoundedWidth;
      final flexes = [for (final child in children) _flexOf(child)];
      final weighted = flexes.any((flex) => flex > 0);
      if (horizontal &&
          mainBounded &&
          !weighted &&
          children.isNotEmpty &&
          children.every((child) => _wrappableTypes.contains(child.type))) {
        return Wrap(
          alignment: _wrapAlignmentOf(justify),
          crossAxisAlignment: _wrapCrossAlignmentOf(align),
          spacing: _rowGap,
          runSpacing: _rowGap,
          children: [for (final child in children) buildChild(child)],
        );
      }
      final share = children.isEmpty
          ? 0.0
          : math.max(
                  0.0,
                  constraints.maxWidth - _rowGap * (children.length - 1),
                ) /
                children.length;
      Widget item(int index) {
        final child = children[index];
        final flex = flexes[index];
        final built = buildChild(child);
        if (!mainBounded) {
          return built;
        }
        if (flex > 0) {
          return Expanded(flex: flex, child: built);
        }
        if (!horizontal) {
          return built;
        }
        // Row 中没有 weight 的文字、输入框等按剩余宽度收缩，避免溢出。
        if (!weighted && !_intrinsicWidthTypes.contains(child.type)) {
          return Flexible(child: built);
        }
        // 与带 weight 的兄弟并排时不参与分配，但宽度不超过均分份额，
        // 内部含 Expanded 的组件也能拿到有界宽度。
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: share),
          child: built,
        );
      }

      return Flex(
        direction: direction,
        mainAxisSize: mainBounded && justify != MainAxisAlignment.start
            ? MainAxisSize.max
            : MainAxisSize.min,
        mainAxisAlignment: justify,
        crossAxisAlignment: align == CrossAxisAlignment.stretch && !crossBounded
            ? CrossAxisAlignment.start
            : align,
        spacing: horizontal ? _rowGap : _columnGap,
        children: [for (var i = 0; i < children.length; i++) item(i)],
      );
    },
  );
}
