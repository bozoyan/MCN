// 职责: 验证聊天发送期间宿主卸载后，不执行依赖 Widget 生命周期的发送收尾。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_send_completion_guard.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/desktop/widgets/ai/chat/runtime.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_send_completion_guard.dart';

void main() {
  testWidgets('发送期间宿主卸载后跳过 UI 收尾', (tester) async {
    final sendCompleter = Completer<void>();
    late BuildContext hostContext;
    var mountedCompletionCalled = false;
    var unmountedCompletionCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await runChatSendWithMountedCompletion(
      context: hostContext,
      send: () => Future<void>.value(),
      onMounted: () => mountedCompletionCalled = true,
    );
    expect(mountedCompletionCalled, isTrue, reason: '宿主存活时仍须执行模型选择等发送收尾');

    final completion = runChatSendWithMountedCompletion(
      context: hostContext,
      send: () => sendCompleter.future,
      onMounted: () => unmountedCompletionCalled = true,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    sendCompleter.complete();
    await completion;

    expect(
      unmountedCompletionCalled,
      isFalse,
      reason: '宿主卸载后不得继续读取 WidgetRef 或更新 Hook 状态',
    );
  });
}
