// 职责: 验证上下文整理进行态嵌入当前 AI 回合，并替换普通打字指示。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/chat/compaction_card.dart
//   lib/shared/widgets/ai/chat/typing_indicator.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tool_activity_group.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_view.dart';
import 'package:reveric/shared/widgets/ai/chat/compaction_card.dart';
import 'package:reveric/shared/widgets/ai/chat/typing_indicator.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('replaces execution card continuation with compaction state', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
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
                child: Scaffold(
                  body: TickerMode(
                    enabled: false,
                    child: ProviderScope(
                      overrides: [
                        aiAgentAvatarPathProvider.overrideWithValue(''),
                        appDebugModeProvider.overrideWithValue(false),
                        isImageGenerationConfiguredProvider.overrideWithValue(
                          false,
                        ),
                      ],
                      child: ChatMessageView(
                        message: const UIMessage(
                          id: 'streaming_1',
                          role: AiMessageRole.assistant,
                          type: AiMessageType.text,
                          content: '',
                          blocks: [
                            AiToolCallBlock(
                              id: 'read_1',
                              callId: 'call_read_1',
                              toolName: 'Read',
                              arguments: {'path': 'chapters/1'},
                              status: AiToolCallStatus.success,
                            ),
                          ],
                          isStreaming: true,
                          isStreamingTail: true,
                          sourceIds: ['streaming_1'],
                        ),
                        activeSessionId: 'session_1',
                        isCompactingContext: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CompactingContextIndicator), findsOneWidget);
    expect(find.byType(AiToolActivityGroup), findsOneWidget);
    expect(find.byType(AiTypingIndicator), findsNothing);
    expect(find.text('Organizing context'), findsOneWidget);
  });
}
