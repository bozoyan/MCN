// 职责: 测试 Todo 面板在受限高度下滚动而不溢出，在不受限高度下按内容收缩或按上限封顶。
// 关联文件:
//   lib/shared/widgets/ai/chat/todo_panel.dart
//   lib/shared/providers/todo_providers.dart
//   lib/desktop/widgets/ai/chat/chat_side_panel.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   assets/translations/en/todo.json
//   assets/translations/zh-CN/todo.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/todo.dart';
import 'package:reveric/shared/providers/todo_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/todo_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('expanded list scrolls when height is constrained', (
    tester,
  ) async {
    final todos = List.generate(
      20,
      (i) => createTodo(content: 'Task $i', sessionId: 's1'),
    );

    // 受限高度：模拟展开模式右侧面板把 TodoPanel 放进 Expanded。
    await tester.pumpWidget(
      _wrap(
        todos: todos,
        child: const SizedBox(
          height: 240,
          width: 338,
          child: TodoPanel(initialExpanded: true, sessionId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Task 0'), findsOneWidget);

    final scrollable = find.descendant(
      of: find.byType(TodoPanel),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Task 19'), findsOneWidget);

    // 不受限高度：面板仍按内容收缩，不占满可用空间。
    await tester.pumpWidget(
      _wrap(
        todos: todos.take(2).toList(),
        child: const SizedBox(
          width: 338,
          child: TodoPanel(initialExpanded: true, sessionId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Task 0'), findsOneWidget);
    expect(find.text('Task 1'), findsOneWidget);
    expect(tester.getSize(find.byType(TodoPanel)).height, lessThan(240));

    // 聊天列顶部：父 Column 给不受限高度，靠 maxListHeight 封顶，
    // 任务再多也不能把下方消息区和 composer 挤出去。
    await tester.pumpWidget(
      _wrap(
        todos: todos,
        child: const SizedBox(
          height: 560,
          width: 338,
          child: Column(
            children: [
              TodoPanel(
                initialExpanded: true,
                sessionId: 's1',
                maxListHeight: TodoPanel.inlineMaxListHeight,
              ),
              Expanded(child: SizedBox.expand()),
              SizedBox(height: 200),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(TodoPanel)).height,
      lessThan(TodoPanel.inlineMaxListHeight + 80),
    );
  });
}

class _FakeSessionTodos extends SessionTodos {
  _FakeSessionTodos(this.todos);

  final List<Todo> todos;

  @override
  Future<List<Todo>> build(String? sessionId) async => todos;
}

Widget _wrap({required List<Todo> todos, required Widget child}) {
  return ProviderScope(
    overrides: [
      sessionTodosProvider('s1').overrideWith(() => _FakeSessionTodos(todos)),
    ],
    child: EasyLocalization(
      key: UniqueKey(),
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(body: Center(child: child)),
            ),
          );
        },
      ),
    ),
  );
}
