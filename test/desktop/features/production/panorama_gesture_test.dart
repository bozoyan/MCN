// 职责: 验证节点内容的旋转手势与实际 ElementScope 节点拖动的竞争。
// 关联文件:
//   lib/third/flow/vyuh_node_flow/lib/src/editor/element_scope.dart
//   lib/shared/widgets/production/panorama/viewer.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/element_scope.dart';

void main() {
  for (final selected in [false, true]) {
    testWidgets('selected=$selected routes body drag to correct owner', (
      tester,
    ) async {
      var moved = 0.0;
      var rotated = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElementScope(
                onDragStart: (_) {},
                onDragUpdate: (details) => moved += details.delta.dx,
                onDragEnd: (_) {},
                child: SizedBox(
                  width: 300,
                  height: 240,
                  child: Column(
                    children: [
                      const SizedBox(
                        key: ValueKey('title'),
                        height: 40,
                        width: 300,
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: selected
                              ? (details) => rotated += details.delta.dx
                              : null,
                          child: const SizedBox(
                            key: ValueKey('body'),
                            width: 300,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('body'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(35, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(35, 0));
      await gesture.up();
      if (selected) {
        expect(rotated, greaterThan(0));
        expect(moved, 0);
      } else {
        expect(moved, greaterThan(0));
        expect(rotated, 0);
      }
      moved = 0;
      rotated = 0;
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('title'))),
        const Offset(70, 0),
        kind: PointerDeviceKind.mouse,
      );
      expect(moved, greaterThan(0));
      expect(rotated, 0);
    });
  }
}
