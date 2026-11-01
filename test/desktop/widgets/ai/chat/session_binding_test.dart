// 职责: 验证 active 延迟加载、空值、刷新、显式选择和作品切换的会话绑定。
// 关联文件:
//   lib/desktop/widgets/ai/chat/session_binding.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/ai/chat/session_binding.dart';

void main() {
  testWidgets(
    'loading never binds, null creates stable draft, refresh and late data preserve selection',
    (tester) async {
      Future<String> render({
        String work = 'a',
        String? selected,
        AsyncValue<String?> data = const AsyncLoading(),
        bool ready = true,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: _Binding(
              work: work,
              selected: selected,
              data: data,
              ready: ready,
            ),
          ),
        );
        return tester.widget<Text>(find.byType(Text)).data!;
      }

      expect(await render(), 'unresolved');
      expect(
        await render(
          data: AsyncError(StateError('read failed'), StackTrace.current),
        ),
        'unresolved',
      );
      expect(
        await render(data: const AsyncData('history_a'), ready: false),
        'unresolved',
      );
      expect(await render(data: const AsyncData('history_a')), 'history_a');
      expect(await render(), 'history_a');
      expect(await render(selected: 'history_b'), 'history_b');
      expect(
        await render(selected: 'history_b', data: const AsyncData('history_a')),
        'history_b',
      );
      expect(await render(work: 'b'), 'unresolved');
      final draft = await render(work: 'b', data: const AsyncData(null));
      expect(draft, startsWith('__new__'));
      expect(await render(work: 'b'), draft);
      expect(await render(work: 'b', data: const AsyncData('late_old')), draft);
      expect(
        await render(
          work: 'c',
          selected: 'explicit',
          data: const AsyncLoading(),
        ),
        'explicit',
      );
      // 换作品那一帧 selectedId 仍是上一部作品的会话（复位 effect 还没跑）：
      // 必须落到新作品的持久化 active，而不是被旧会话锁死。
      expect(
        await render(
          work: 'd',
          selected: 'explicit',
          data: const AsyncData('history_d'),
        ),
        'history_d',
      );
      expect(
        await render(work: 'd', data: const AsyncData('history_d')),
        'history_d',
      );
      expect(await render(work: 'd', selected: 'picked_d'), 'picked_d');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

class _Binding extends HookWidget {
  const _Binding({
    required this.work,
    required this.selected,
    required this.data,
    required this.ready,
  });
  final String work;
  final String? selected;
  final AsyncValue<String?> data;
  final bool ready;
  @override
  Widget build(BuildContext context) => Text(
    useResolvedChatSession(
          novelId: work,
          databasePath: '$work.sqlite',
          ready: ready,
          selectedId: selected,
          persisted: data,
        ) ??
        'unresolved',
  );
}
