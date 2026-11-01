// 职责: 验证横向滚动区域接管鼠标纵向滚轮，并在滚到尽头时把事件让给外层纵向滚动。
// 关联文件:
//   lib/shared/components/horizontal_wheel_scroll.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/horizontal_wheel_scroll.dart';

void main() {
  testWidgets('maps vertical wheel deltas onto the horizontal axis', (
    tester,
  ) async {
    late ScrollController horizontal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: HorizontalWheelScroll(
              builder: (context, controller) {
                horizontal = controller;
                return SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 900, height: 120),
                );
              },
            ),
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(SingleChildScrollView)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(horizontal.offset, 120);

    // 反向滚轮回到起点，且不会滚过头。
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -400)));
    await tester.pump();

    expect(horizontal.offset, 0);
  });

  testWidgets('leaves events that already carry a horizontal delta alone', (
    tester,
  ) async {
    late ScrollController horizontal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: HorizontalWheelScroll(
              builder: (context, controller) {
                horizontal = controller;
                return SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 900, height: 120),
                );
              },
            ),
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(SingleChildScrollView)));
    // dx 存在时由 Scrollable 原生处理，dy 不能再被叠加成第二次横向滚动。
    await tester.sendEventToBinding(pointer.scroll(const Offset(30, 100)));
    await tester.pump();

    expect(horizontal.offset, 30);
  });

  testWidgets('leaves the wheel to a nested vertical scrollable', (
    tester,
  ) async {
    late ScrollController horizontal;
    final inner = ScrollController();
    addTearDown(inner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: HorizontalWheelScroll(
              builder: (context, controller) {
                horizontal = controller;
                return SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 900,
                    child: ListView(
                      controller: inner,
                      children: const [SizedBox(height: 1200)],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    // ListView 有 900 宽、大半在视口外，取视口中心才落在它可见的那段上。
    pointer.hover(tester.getCenter(find.byType(SingleChildScrollView)));
    // 命中更深的纵向 scrollable 先登记，滚轮归它。
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(inner.offset, 120);
    expect(horizontal.offset, 0);

    // 内层滚到尽头后不再登记，滚轮才回到横向。
    inner.jumpTo(inner.position.maxScrollExtent);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(inner.offset, inner.position.maxScrollExtent);
    expect(horizontal.offset, 120);
  });

  testWidgets('yields the wheel to an outer vertical scrollable at the end', (
    tester,
  ) async {
    late ScrollController horizontal;
    final vertical = ScrollController();
    addTearDown(vertical.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: vertical,
            children: [
              SizedBox(
                height: 120,
                child: HorizontalWheelScroll(
                  builder: (context, controller) {
                    horizontal = controller;
                    return SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: const SizedBox(width: 2000, height: 120),
                    );
                  },
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(SingleChildScrollView)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(horizontal.offset, 120);
    expect(vertical.offset, 0);

    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(vertical.offset, 120);
  });
}
