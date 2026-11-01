// 职责: 给横向滚动区域补上鼠标滚轮支持 — 把纯纵向滚轮增量映射成横向偏移。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_timeline_strip.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 横向滚动区域的鼠标滚轮适配层。
///
/// `Scrollable` 在横向轴上只读 `scrollDelta.dx`，而普通鼠标滚轮只产生 dy，
/// 所以桌面端横向列表默认「滚轮转了没反应」。本组件把纯纵向滚轮换算成横向偏移；
/// 横向滚轮、触控板横扫、Shift+滚轮仍由 `Scrollable` 原生处理。
///
/// 与其他纵向滚动区域的优先级由 `pointerSignalResolver` 决定，先登记者赢，
/// 而命中测试是由内向外的：
/// - 本区域内部的纵向滚动（看板列等）命中更深、先登记，纵向滚轮仍归它；
/// - 外层纵向页面命中更浅，只有本区域滚到尽头放弃登记时才拿到滚轮。
///
/// 所以嵌在纵向页面里不会把页面卡死，但鼠标停在本区域上时，页面要等这里滚到头
/// 才继续。横向滚动不是主要操作的区域（宽表格、图表）别用，改配横向滚动条。
///
/// ```dart
/// HorizontalWheelScroll(
///   builder: (context, controller) => SingleChildScrollView(
///     controller: controller,
///     scrollDirection: Axis.horizontal,
///     child: ...,
///   ),
/// )
/// ```
class HorizontalWheelScroll extends HookWidget {
  const HorizontalWheelScroll({
    super.key,
    this.controller,
    required this.builder,
  });

  /// 外部已持有 controller 时传入；不传则内部创建并自动 dispose。
  final ScrollController? controller;

  /// 回调拿到的 controller 必须交给横向 scroll view，否则滚轮无处生效。
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  Widget build(BuildContext context) {
    final internalController = useScrollController();
    final scrollController = controller ?? internalController;

    return Listener(
      onPointerSignal: (event) => _handlePointerSignal(event, scrollController),
      child: builder(context, scrollController),
    );
  }

  static void _handlePointerSignal(
    PointerSignalEvent event,
    ScrollController controller,
  ) {
    if (event is! PointerScrollEvent) {
      return;
    }
    // 带横向分量的事件（横向滚轮 / 触控板横扫）Scrollable 自己能处理，别抢。
    if (event.scrollDelta.dx != 0) {
      return;
    }
    final delta = event.scrollDelta.dy;
    // 同一个 controller 挂了多个 scroll view 时 `position` 会断言失败，直接放行。
    if (delta == 0 || controller.positions.length != 1) {
      return;
    }
    final position = controller.position;
    if (!position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final target = math.min(
      math.max(position.pixels + delta, position.minScrollExtent),
      position.maxScrollExtent,
    );
    // 已经滚到头就不登记，把事件让给外层，避免整块区域吞掉滚轮。
    if (target == position.pixels) {
      return;
    }
    // 走 resolver 而不是直接改 offset：同一个 pointer signal 只允许一个
    // scrollable 消费，内层先登记的（如 Shift+滚轮）赢，外层也不会跟着滚。
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      position.pointerScroll(delta);
      (resolved as PointerScrollEvent).respond(allowPlatformDefault: false);
    });
  }
}
