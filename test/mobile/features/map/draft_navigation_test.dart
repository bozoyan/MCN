// 职责: 验证 Agent 制图草案的跳转时机 — 轮中只记下目标，这一轮说完才走；
//       从工作台进来时带着目标关页（连同上层 sheet），否则在当前页之上打开地图。
// 关联文件:
//   lib/mobile/features/map/draft_navigation.dart
//   lib/mobile/pages/novel_chat_page.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/features/map/draft_navigation.dart';

void main() {
  testWidgets('waits for the turn, then returns the target to the caller', (
    tester,
  ) async {
    final processing = ValueNotifier(true);
    late ValueNotifier<String?> pending;
    String? returned;
    final opened = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => ValueListenableBuilder<bool>(
                    valueListenable: processing,
                    builder: (_, busy, _) => HookBuilder(
                      builder: (context) {
                        pending = useMapDraftNavigation(
                          context,
                          processing: busy,
                          returnToCaller: true,
                          openMap: opened.add,
                        );
                        return const Scaffold(body: Text('chat'));
                      },
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 轮中提交：只记下，不离开。
    pending.value = 'city';
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);

    // 上层还盖着一个 sheet：一并收掉。
    showModalBottomSheet<void>(
      context: tester.element(find.text('chat')),
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    processing.value = false;
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsNothing);
    expect(find.text('sheet'), findsNothing);
    expect(returned, 'city');
    expect(opened, isEmpty);

    // 另一种入口：不返回调用方，而是在当前页之上打开地图。
    final processing2 = ValueNotifier(true);
    late ValueNotifier<String?> pending2;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: processing2,
          builder: (_, busy, _) => HookBuilder(
            builder: (context) {
              pending2 = useMapDraftNavigation(
                context,
                processing: busy,
                returnToCaller: false,
                openMap: opened.add,
              );
              return const Scaffold(body: Text('chat2'));
            },
          ),
        ),
      ),
    );
    pending2.value = 'world';
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    processing2.value = false;
    await tester.pumpAndSettle();
    expect(opened, ['world']);
    expect(find.text('chat2'), findsOneWidget);
    expect(pending2.value, isNull);
  });
}
