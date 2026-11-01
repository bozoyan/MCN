// 职责: 锁定小说编辑器 AI 区拖拽贴合不能走 AnimatedSize+Duration.zero。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/novel_editor_ai_area.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Novel editor snaps AI pane width while dragging by omitting [AnimatedSize].
/// Using [AnimatedSize] with [Duration.zero] re-dirties RenderAnimatedSize
/// inside performLayout when the child size changes (Flutter framework).
Widget _aiAreaShell({required bool dragging, required double width}) {
  final child = SizedBox(width: width, height: 40, key: ValueKey(width));
  if (dragging) {
    return child;
  }
  return AnimatedSize(
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    alignment: Alignment.centerRight,
    clipBehavior: Clip.hardEdge,
    child: child,
  );
}

void main() {
  testWidgets(
    'drag snap omits AnimatedSize so width changes do not mutate during layout',
    (tester) async {
      var width = 100.0;
      const dragging = true;
      final errors = <Object>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details.exception);
      };
      addTearDown(() {
        FlutterError.onError = oldHandler;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  _aiAreaShell(dragging: dragging, width: width),
                  TextButton(
                    onPressed: () => setState(() => width += 40),
                    child: const Text('resize'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('resize'));
      await tester.pump();
      await tester.tap(find.text('resize'));
      await tester.pump();

      expect(errors, isEmpty);
      expect(find.byType(AnimatedSize), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey(180.0))).width, 180);
    },
  );

  testWidgets('AnimatedSize with Duration.zero still throws on size change', (
    tester,
  ) async {
    var width = 100.0;
    final errors = <Object>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exception);
    };
    addTearDown(() {
      FlutterError.onError = oldHandler;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                AnimatedSize(
                  duration: Duration.zero,
                  child: SizedBox(width: width, height: 40),
                ),
                TextButton(
                  onPressed: () => setState(() => width = 180),
                  child: const Text('grow'),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('grow'));
    await tester.pump();

    expect(
      errors.any((e) => e.toString().contains('RenderAnimatedSize')),
      isTrue,
      reason:
          'Duration.zero must keep failing so the drag-snap bypass stays justified',
    );
  });
}
