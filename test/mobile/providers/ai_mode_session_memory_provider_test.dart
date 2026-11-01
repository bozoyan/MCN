// 职责: 测试移动端 AI 模式 tab 进程内会话记忆 — remember/clear、忽略临时 draft、按作品隔离。
// 关联文件:
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/mobile/widgets/mobile_ai_mode.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/providers/ai_mode_session_memory_provider.dart';
import 'package:reveric/mobile/widgets/mobile_ai_mode.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';

void main() {
  group('isRememberableAiModeSessionId', () {
    test('真实 id 可记忆，临时 draft / 空值不可', () {
      expect(isRememberableAiModeSessionId('sess_1'), isTrue);
      expect(
        isRememberableAiModeSessionId('__new__mobile_chat_draft_1'),
        isFalse,
      );
      expect(isRememberableAiModeSessionId('__handoff_draft__abc'), isFalse);
      expect(isRememberableAiModeSessionId(null), isFalse);
      expect(isRememberableAiModeSessionId(''), isFalse);
    });
  });

  group('mobileAiModeSessionMemoryProvider', () {
    test('remember 写入、临时 draft 清除、按 novelId 隔离', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final novelA = container.read(
        mobileAiModeSessionMemoryProvider('novel-a').notifier,
      );
      final novelB = container.read(
        mobileAiModeSessionMemoryProvider('novel-b').notifier,
      );

      novelA.remember(AiSessionMode.chat, 'chat-a');
      novelA.remember(AiSessionMode.council, 'council-a');
      novelB.remember(AiSessionMode.chat, 'chat-b');

      expect(novelA.sessionIdFor(AiSessionMode.chat), 'chat-a');
      expect(novelA.sessionIdFor(AiSessionMode.council), 'council-a');
      expect(novelB.sessionIdFor(AiSessionMode.chat), 'chat-b');
      expect(novelB.sessionIdFor(AiSessionMode.council), isNull);

      novelA.remember(AiSessionMode.chat, '__new__draft');
      expect(novelA.sessionIdFor(AiSessionMode.chat), isNull);
      expect(novelA.sessionIdFor(AiSessionMode.council), 'council-a');

      novelA.clear(AiSessionMode.council);
      expect(novelA.sessionIdFor(AiSessionMode.council), isNull);
    });
  });

  group('resolveMobileAiModeTargetSessionId', () {
    test('显式 id 优先于记忆与 preferred', () {
      expect(
        resolveMobileAiModeTargetSessionId(
          targetMode: AiSessionMode.chat,
          existingSessionId: 'explicit',
          rememberedSessionId: 'remembered',
          preferredChatSessionId: 'preferred',
        ),
        'explicit',
      );
    });

    test('无显式 id 时用记忆；chat 再回落 preferred', () {
      expect(
        resolveMobileAiModeTargetSessionId(
          targetMode: AiSessionMode.council,
          rememberedSessionId: 'council-1',
          preferredChatSessionId: 'preferred',
        ),
        'council-1',
      );
      expect(
        resolveMobileAiModeTargetSessionId(
          targetMode: AiSessionMode.chat,
          preferredChatSessionId: 'preferred',
        ),
        'preferred',
      );
      expect(
        resolveMobileAiModeTargetSessionId(
          targetMode: AiSessionMode.council,
          preferredChatSessionId: 'preferred',
        ),
        isNull,
      );
    });

    test('新建会话关闭恢复时不读记忆与 preferred', () {
      expect(
        resolveMobileAiModeTargetSessionId(
          targetMode: AiSessionMode.chat,
          rememberedSessionId: 'remembered',
          preferredChatSessionId: 'preferred',
          restoreRemembered: false,
          useChatPreferredFallback: false,
        ),
        isNull,
      );
    });
  });
}
