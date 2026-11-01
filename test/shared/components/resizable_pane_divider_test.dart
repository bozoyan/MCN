// 职责: 验证分栏仅留细线、两侧拖拽热区与动画边界同步，并在边界隐藏后释放点击。
// 关联文件:
//   lib/shared/components/resizable_pane_divider.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/resizable_pane_divider.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'thin boundary keeps a usable drag target on $platform',
      (tester) async {
        final link = LayerLink();
        var paneWidth = 200.0;
        var visible = true;
        var delta = 0.0;
        var commits = 0;
        var paneTaps = 0;
        late StateSetter update;
        const leftKey = ValueKey('left-pane');
        const rightKey = ValueKey('right-pane');

        Widget pane(Key key, Color color) => GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => paneTaps++,
          child: SizedBox.expand(child: ColoredBox(color: color)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    final colors = RevericTheme.colorsOf(context);
                    return Stack(
                      children: [
                        Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: paneWidth,
                              child: pane(leftKey, colors.surfaceDim),
                            ),
                            if (visible) ResizablePaneDividerAnchor(link: link),
                            Expanded(child: pane(rightKey, colors.surface)),
                          ],
                        ),
                        ResizablePaneDivider(
                          link: link,
                          onDragUpdate: (dx) => delta += dx,
                          onDragEnd: () => commits++,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        void expectThinBoundary() {
          final left = tester.getRect(find.byKey(leftKey));
          final right = tester.getRect(find.byKey(rightKey));
          expect(right.left - left.right, 1);
          final line = tester.getRect(find.byType(ResizablePaneDividerAnchor));
          expect(line.width, 1);
          expect(line.height, left.height);
          expect(line.top, left.top);
        }

        expectThinBoundary();
        // Both sides are outside the 1px line, but inside the 10px drag target.
        for (final offset in [-4.0, 4.0]) {
          final line = tester.getRect(find.byType(ResizablePaneDividerAnchor));
          final before = delta;
          await tester.dragFrom(
            line.center + Offset(offset, 0),
            const Offset(48, 0),
            kind: PointerDeviceKind.mouse,
          );
          expect(delta, greaterThan(before));
        }
        expect(commits, 2);
        expect(paneTaps, 0);
        final line = tester.getRect(find.byType(ResizablePaneDividerAnchor));
        await tester.tapAt(line.center + const Offset(-8, 0));
        await tester.tapAt(line.center + const Offset(8, 0));
        expect(paneTaps, 2);

        // The anchor moves during animation without rebuilding the follower.
        update(() => paneWidth = 320);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expectThinBoundary();
        final movingLine = tester.getRect(
          find.byType(ResizablePaneDividerAnchor),
        );
        expect(movingLine.left, greaterThan(200));
        expect(movingLine.left, lessThan(320));
        final before = delta;
        final drag = await tester.startGesture(
          movingLine.center + const Offset(4, 0),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(48, 0));
        await drag.up();
        expect(delta, greaterThan(before));
        expect(commits, 3);
        await tester.pumpAndSettle();
        expectThinBoundary();

        final oldBoundary = tester
            .getRect(find.byType(ResizablePaneDividerAnchor))
            .center;
        update(() => visible = false);
        await tester.pump();
        await tester.tapAt(oldBoundary);
        expect(paneTaps, 3);
        expect(commits, 3);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
