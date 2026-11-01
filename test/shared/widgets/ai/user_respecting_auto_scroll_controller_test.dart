// 职责: 验证流式贴底能持续跟随，且用户回看历史时不被打断、能正确恢复
// 关联文件:
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/user_respecting_auto_scroll_controller.dart';

const _itemExtent = 96.0;
const _viewportHeight = 320.0;

void main() {
  testWidgets('streaming updates keep the list pinned to the bottom', (
    tester,
  ) async {
    // 回归：贴底若用 animateTo，连续流式更新会不断抢占重建动画，滚动位置几乎不推进，
    // 随后这份滞后被误判成「用户上滑」而永久关闭跟随。必须每帧 jumpTo。
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 1)));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;

    for (var count = 2; count <= 30; count++) {
      await tester.pumpWidget(
        _wrap(_Harness(itemCount: count, streaming: true)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(position.maxScrollExtent, 30 * _itemExtent - _viewportHeight);
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('scrollback survives streaming and resumes at the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 1)));
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 12)));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, position.maxScrollExtent);

    await tester.drag(find.byType(ListView), const Offset(0, 260));
    await tester.pumpAndSettle();
    final scrollbackOffset = position.pixels;
    expect(scrollbackOffset, lessThan(position.maxScrollExtent));

    // 回看期间持续流式：不能把用户拽回底部。
    for (var count = 13; count <= 20; count++) {
      await tester.pumpWidget(
        _wrap(_Harness(itemCount: count, streaming: true)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(position.pixels, scrollbackOffset);

    // 用户自己滑回底部 → 恢复跟随。
    await _dragToBottom(tester, position);
    expect(position.pixels, position.maxScrollExtent);

    await tester.pumpWidget(_wrap(const _Harness(itemCount: 24)));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('a small nudge within the bottom tolerance keeps following', (
    tester,
  ) async {
    // 回归：40px 的轻推仍在 48px 容差内，不应被当成回看历史而永久关闭跟随。
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 1)));
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 12)));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, position.maxScrollExtent);

    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(const _Harness(itemCount: 20)));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('dragging a nested scrollable does not pause the outer list', (
    tester,
  ) async {
    // 回归：卡片内横向滚动区的通知会冒泡到外层 NotificationListener，
    // 不加 depth 过滤会被误判成用户在回看本列表历史。
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 1, nested: true)));
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 12, nested: true)));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);

    await tester.drag(
      find.byKey(const ValueKey('nested-11')),
      const Offset(-60, 0),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(const _Harness(itemCount: 20, nested: true)));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('switching sessions resumes following', (tester) async {
    // 回归：上个会话的回看状态不能带到新会话，否则新会话永远不贴底。
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 1)));
    await tester.pumpWidget(_wrap(const _Harness(itemCount: 12)));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;

    await tester.drag(find.byType(ListView), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(position.maxScrollExtent));

    await tester.pumpWidget(
      _wrap(const _Harness(itemCount: 20, sessionId: 'session-2')),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
  });
}

/// 分段下滑到底部。lazy 列表单次拖动最多只能跨越已布局的范围，
/// 一次性拖一大段会被 clamp 在中途，与真实用户的连续滑动不符。
Future<void> _dragToBottom(WidgetTester tester, ScrollPosition position) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (position.pixels >= position.maxScrollExtent) {
      return;
    }
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 360, height: _viewportHeight, child: child),
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.itemCount,
    this.streaming = false,
    this.sessionId = 'session-1',
    this.nested = false,
  });

  final int itemCount;
  final bool streaming;
  final String sessionId;
  final bool nested;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant _Harness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _autoScroll.resumeFollow();
    }
    if (oldWidget.itemCount != widget.itemCount) {
      _autoScroll.scheduleScrollToBottom(streaming: widget.streaming);
    }
  }

  @override
  void dispose() {
    _autoScroll.dispose();
    super.dispose();
  }

  Widget _item(int index) {
    return SizedBox(
      height: _itemExtent,
      child: widget.nested
          ? ListView(
              key: ValueKey('nested-$index'),
              scrollDirection: Axis.horizontal,
              children: [SizedBox(width: 900, child: Text('message $index'))],
            )
          : Text('message $index'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView.builder(
        controller: _autoScroll.scrollController,
        itemCount: widget.itemCount,
        itemBuilder: (_, index) => _item(index),
      ),
    );
  }
}
