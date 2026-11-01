// 职责: 验证 AI 处理中退出流程在页面已被关闭后恢复执行时，不会误关下层页面。
// 关联文件:
//   lib/shared/utils/route_pop.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/desktop/pages/novel_editor.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/route_pop.dart';

/// 复现聊天页 / 编辑器的退出流程：PopScope 拦截 → 确认弹窗 → 下一帧关闭本页。
class _ExitGuardedPage extends StatelessWidget {
  const _ExitGuardedPage();

  @override
  Widget build(BuildContext context) {
    Future<void> handleProcessingExit() async {
      final decision = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('continue'),
        ),
      );
      if (decision != true) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
      if (context.mounted) {
        popIfRouteCurrent(context);
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          handleProcessingExit();
        }
      },
      child: const Text('page'),
    );
  }
}

void main() {
  Future<NavigatorState> pumpGuardedPage(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );
    final navigator = navigatorKey.currentState!;
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const _ExitGuardedPage()),
    );
    await tester.pumpAndSettle();
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('continue'), findsOneWidget);
    return navigator;
  }

  testWidgets('确认退出后关闭本页', (tester) async {
    await pumpGuardedPage(tester);

    await tester.tap(find.text('continue'));
    await tester.pumpAndSettle();

    expect(find.text('page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('等待期间本页已被关闭时不再 pop 下层页面', (tester) async {
    final navigator = await pumpGuardedPage(tester);

    // 选择后、退出流程恢复执行前，第二次返回手势已把本页关掉。
    await tester.tap(find.text('continue'));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
