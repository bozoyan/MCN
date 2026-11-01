// 职责: 验证工具参数流不完整时，普通模式隐藏内部诊断且未执行。
// 关联文件:
//   lib/shared/widgets/ai/tool_activity_group.dart
//   lib/shared/widgets/ai/tools/tool_card_descriptor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tool_activity_group.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_card_common.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_card_descriptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('ignores non-string path in tool arguments and result', () {
    const block = AiToolCallBlock(
      id: 'run_path_object',
      callId: 'call_run_path_object',
      toolName: 'RunCommand',
      arguments: {
        'path': {'points': <Object>[]},
      },
      status: AiToolCallStatus.success,
      result: {
        'path': {'points': <Object>[]},
      },
    );

    expect(toolResultResourcePath(block.result), isNull);
    expect(toolPrimaryPath(block), isNull);
  });

  testWidgets('hides incomplete tool call failure outside debug mode', (
    tester,
  ) async {
    const incompleteBlock = AiToolCallBlock(
      id: 'edit_incomplete',
      callId: 'call_edit_incomplete',
      toolName: 'Edit',
      arguments: {'path': '/chapters/1'},
      status: AiToolCallStatus.error,
      result: {'error_code': 'tool_call_incomplete'},
    );
    expect(isIncompleteAiToolCall(incompleteBlock), isTrue);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => ProviderScope(
            overrides: [appDebugModeProvider.overrideWithValue(false)],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: const Scaffold(
                  body: AiToolActivityGroup(blocks: [incompleteBlock]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(AiToolStatusDot), findsNothing);
    expect(
      find.text(
        'Tool parameters were received incompletely. The tool was not run.',
      ),
      findsNothing,
    );
  });
}
