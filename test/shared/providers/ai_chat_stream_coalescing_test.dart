// 职责: 验证 AiChatSession streaming delta 通知合帧 — state 实时更新、通知按窗口节流、正常变更立即通知
// 关联文件:
//   lib/shared/providers/ai_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/providers/ai_providers.dart';

// 合帧的意义：streaming 时每个 delta 都触发整棵聊天面板重建（profile 实测
// 单次 ~50ms），逐 chunk 通知会吃满 CPU。这里锁定三个行为契约：
// 1) state 永远实时 —— 任何 ref.read 立即看到全部已到达的 delta；
// 2) 通知被窗口节流 —— delta 风暴期间 listener 不会每 chunk 被调一次；
// 3) 低频正常变更（如 endStreamingMessage）不受节流影响，立即通知且携带最新内容。
void main() {
  const window = Duration(milliseconds: 100);

  group('AiChatSession streaming notification coalescing', () {
    test(
      'delta storm updates state in real time but coalesces notifications',
      () {
        fakeAsync((async) {
          final container = ProviderContainer();

          final notifier = container.read(
            aiChatSessionProvider('sess_coalesce').notifier,
          );
          notifier.startStreamingMessage();

          var notifications = 0;
          container.listen(
            aiChatSessionProvider('sess_coalesce'),
            (_, _) => notifications++,
          );

          for (var i = 0; i < 50; i++) {
            notifier.appendTextDelta('d$i ');
          }

          // 窗口内：只有首个 delta 的 leading-edge 通知。
          expect(notifications, 1);
          // 但 state 实时包含全部 50 个 delta —— 节流只影响通知，不影响读取。
          final live = container.read(aiChatSessionProvider('sess_coalesce'));
          expect(live.messages.single.content, contains('d0 '));
          expect(live.messages.single.content, contains('d49 '));

          // 窗口结束：积压内容以一次 trailing-edge 通知补发。
          async.elapse(window + const Duration(milliseconds: 20));
          expect(notifications, 2);

          // 无新 delta 后不再产生空通知。
          async.elapse(window * 3);
          expect(notifications, 2);

          container.dispose();
        });
      },
    );

    test(
      'non-delta mutation mid-window notifies immediately and clears backlog',
      () {
        fakeAsync((async) {
          final container = ProviderContainer();

          final notifier = container.read(
            aiChatSessionProvider('sess_flush').notifier,
          );
          notifier.startStreamingMessage();

          var notifications = 0;
          String? lastSeenContent;
          container.listen(aiChatSessionProvider('sess_flush'), (_, next) {
            notifications++;
            lastSeenContent = next.messages.single.content;
          });

          notifier.appendTextDelta('hello '); // leading edge → 通知 1
          notifier.appendTextDelta('world'); // 窗口内 → 被合帧
          expect(notifications, 1);

          // 结束流式：立即通知，且 listener 看到的是含全部 delta 的最新 state。
          notifier.endStreamingMessage();
          expect(notifications, 2);
          expect(lastSeenContent, 'hello world');
          expect(
            container
                .read(aiChatSessionProvider('sess_flush'))
                .messages
                .single
                .isStreaming,
            isFalse,
          );

          // 正常通知已携带最新内容，窗口到期不再补发积压通知。
          async.elapse(window * 2);
          expect(notifications, 2);

          container.dispose();
        });
      },
    );
  });
}
