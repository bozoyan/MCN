// 职责: 桌面聊天输入区动作判定回归测试 — 覆盖空内容、handoff、排队与停止边界。
// 关联文件:
//   lib/desktop/widgets/ai/chat/composer.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/ai/chat/composer.dart';

void main() {
  test('resolves send, queue, stop, and disabled actions consistently', () {
    DesktopChatComposerAction resolve({
      bool isConfigured = true,
      bool isRequestInFlight = false,
      String draftText = '',
      bool hasPendingHandoff = false,
      bool queueOccupied = false,
    }) {
      return resolveDesktopChatComposerAction(
        isConfigured: isConfigured,

        isRequestInFlight: isRequestInFlight,
        draftText: draftText,
        hasPendingHandoff: hasPendingHandoff,
        queueOccupied: queueOccupied,
      );
    }

    expect(resolve(), DesktopChatComposerAction.disabled);
    expect(resolve(draftText: '   '), DesktopChatComposerAction.disabled);
    expect(resolve(draftText: 'hello'), DesktopChatComposerAction.send);
    expect(resolve(hasPendingHandoff: true), DesktopChatComposerAction.send);
    expect(
      resolve(draftText: 'hello', isConfigured: false),
      DesktopChatComposerAction.disabled,
    );
    expect(resolve(isRequestInFlight: true), DesktopChatComposerAction.stop);
    expect(
      resolve(isRequestInFlight: true, draftText: 'queued'),
      DesktopChatComposerAction.queue,
    );
    expect(
      resolve(
        isRequestInFlight: true,
        draftText: 'queued',
        queueOccupied: true,
      ),
      DesktopChatComposerAction.stop,
    );
    expect(
      resolve(isConfigured: false, isRequestInFlight: true),
      DesktopChatComposerAction.disabled,
    );
  });
}
