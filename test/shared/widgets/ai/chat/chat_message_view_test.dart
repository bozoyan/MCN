// 职责: 测试共享聊天消息渲染对特殊消息类型的展示分流。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/chat/ui_message.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_parts.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_view.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // 注：本文件保持单个 testWidgets。appSettingsProvider 等 keepAlive provider
  // 经 AppDatabase() 静态缓存跨测试复用，第二个 testWidgets 会拿到脏状态
  // （见 .agents/rules/testing.md），因此新断言并入本用例而非另开测试。
  testWidgets(
    'renders compact summaries, inline references and slash chips without leaking content',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'historical_question',
                      role: AiMessageRole.assistant,
                      type: AiMessageType.text,
                      content: '',
                      blocks: [
                        AiAskUserBlock(
                          id: 'historical_block',
                          callId: 'historical_call',
                          questions: [],
                        ),
                      ],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['historical_question'],
                    ),
                    activeSessionId: 'historical_session',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'summary_1',
                      role: AiMessageRole.user,
                      type: AiMessageType.compact_summary,
                      content:
                          'The retained context begins at the current task.',
                      blocks: [],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['summary_1'],
                    ),
                    activeSessionId: 'session_1',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'user_file_1',
                      role: AiMessageRole.user,
                      type: AiMessageType.text,
                      content:
                          "<user-remind type='file' label='notes.md'>"
                          '<file-content>private source text</file-content>'
                          '</user-remind>\nSummarize it',
                      blocks: [],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['user_file_1'],
                    ),
                    activeSessionId: 'session_1',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'user_selection_1',
                      role: AiMessageRole.user,
                      type: AiMessageType.text,
                      content:
                          "<user-remind type='selection' label='Chapter 1'>"
                          '<selection-content>private excerpt</selection-content>'
                          '</user-remind>\nAnalyze it',
                      blocks: [],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['user_selection_1'],
                    ),
                    activeSessionId: 'session_1',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'user_skill_1',
                      role: AiMessageRole.user,
                      type: AiMessageType.text,
                      content: '可以开始写第5章了',
                      blocks: [],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['user_skill_1'],
                      metadata: {
                        'skill_names': ['正文写手'],
                        'subagent_names': ['剧情顾问'],
                      },
                    ),
                    activeSessionId: 'session_1',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'user_plain_1',
                      role: AiMessageRole.user,
                      type: AiMessageType.text,
                      content: '普通消息',
                      blocks: [],
                      isStreaming: false,
                      isStreamingTail: false,
                      sourceIds: ['user_plain_1'],
                    ),
                    activeSessionId: 'session_1',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'assistant_waiting_1',
                      role: AiMessageRole.assistant,
                      type: AiMessageType.text,
                      content: '',
                      blocks: [],
                      isStreaming: true,
                      isStreamingTail: true,
                      sourceIds: ['assistant_waiting_1'],
                    ),
                    activeSessionId: 'session_1',
                    isWaitingForResponse: true,
                    retryProgress: '1/4',
                  ),
                  ChatMessageView(
                    message: const UIMessage(
                      id: 'assistant_waiting_after_todo_1',
                      role: AiMessageRole.assistant,
                      type: AiMessageType.text,
                      content: '',
                      blocks: [
                        AiToolCallBlock(
                          id: 'todo_1',
                          callId: 'call_todo_1',
                          toolName: 'TodoWrite',
                          arguments: {},
                          status: AiToolCallStatus.success,
                        ),
                      ],
                      isStreaming: true,
                      isStreamingTail: true,
                      sourceIds: ['assistant_waiting_after_todo_1'],
                    ),
                    activeSessionId: 'session_1',
                    isWaitingForResponse: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatMessageView), findsNWidgets(8));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageView).first),
      );
      expect(
        container.exists(aiChatRuntimeProvider('historical_session')),
        isFalse,
      );
      expect(find.text('Interrupted'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Context organized'), findsOneWidget);
      expect(
        find.text('The retained context begins at the current task.'),
        findsNothing,
      );
      expect(find.text('File · notes.md'), findsOneWidget);
      expect(find.text('Summarize it'), findsOneWidget);
      expect(find.text('Excerpt · Chapter 1'), findsOneWidget);
      expect(find.text('Analyze it'), findsOneWidget);
      expect(find.textContaining('private source text'), findsNothing);
      expect(find.textContaining('private excerpt'), findsNothing);
      // 带 skill_names / subagent_names metadata 的用户消息：正文与两类 chip 都可见；
      // 无 metadata 的普通消息不渲染 chip。
      expect(find.text('可以开始写第5章了'), findsOneWidget);
      expect(find.text('正文写手'), findsOneWidget);
      expect(find.text('剧情顾问'), findsOneWidget);
      expect(find.byType(SkillUsedChip), findsOneWidget);
      expect(find.byType(SubagentUsedChip), findsOneWidget);
      expect(find.text('普通消息'), findsOneWidget);
      expect(find.text('Thinking...'), findsOneWidget);
      expect(
        find.text('Response interrupted, retrying (1/4)…'),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(const Size(320, 800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
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
            child: Scaffold(body: TickerMode(enabled: false, child: child)),
          ),
        );
      },
    ),
  );
}
