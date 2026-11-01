// 职责: 验证 Write 工具卡片能安全处理非文本 value 参数，并标出被锁定的已发布章节。
// 关联文件:
//   lib/shared/widgets/ai/tools/write_tool_card_body.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/services/ai/tool_error_normalize.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/chapter.json
//   assets/translations/zh-CN/chapter.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/services/ai/tool_error_normalize.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tools/write_tool_card_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('does not crash when Write value is an integer', (tester) async {
    const block = AiToolCallBlock(
      id: 'block_write',
      callId: 'call_write',
      toolName: 'Write',
      arguments: {'path': '/chapters/chapter_1/chapter_num', 'value': 1},
    );

    await tester.pumpWidget(_wrap(const WriteToolCardBody(block: block)));

    expect(tester.takeException(), isNull);
  });

  testWidgets('marks a locked chapter write as published', (tester) async {
    final block = AiToolCallBlock(
      id: 'block_write_locked',
      callId: 'call_write_locked',
      toolName: 'Write',
      arguments: const {'path': '/chapters/chapter_1/content', 'value': '新正文'},
      status: AiToolCallStatus.error,
      result: {
        'ok': false,
        'error': 'Chapter "chapter_1" is published.',
        'error_code': ToolErrorCode.locked.name,
      },
    );

    await tester.pumpWidget(_wrap(WriteToolCardBody(block: block)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Published'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
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
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}
