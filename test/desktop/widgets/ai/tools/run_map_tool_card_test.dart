// 职责: 验证地图 Run 工具卡 — 使用本地化语义文案并隐藏原始英文输出。
// 关联文件:
//   lib/shared/widgets/ai/tools/run_tool_card_body.dart
//   lib/shared/widgets/ai/tools/tool_card_descriptor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tools/run_tool_card_body.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_card_descriptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('localizes map draft card and does not show raw output', (
    tester,
  ) async {
    const block = AiToolCallBlock(
      id: 'block_1',
      callId: 'call_1',
      toolName: 'Run',
      arguments: {
        'command': 'map',
        'subcommand': 'draft',
        'options': {
          'prompt': '绘制一张水彩绘本地图',
          'style': 'watercolor',
          'resolution': '2k',
          'quality': 'medium',
        },
      },
      status: AiToolCallStatus.success,
      result: {
        'ok': true,
        'command': 'map draft',
        'output': 'Map design draft is ready for review in Cartographer.',
      },
    );

    late String title;
    late String verb;
    late String? target;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            title = localizedToolCallTitle(context, block);
            verb = toolActionVerb(context, block);
            target = toolRowTarget(context, block, null);
            return const RunToolCardBody(block: block);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(title, '提交地图草稿');
    expect(verb, '提交地图草稿');
    expect(target, isNull);
    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('水彩绘本'), findsOneWidget);
    expect(find.text('中等质量'), findsOneWidget);
    expect(find.text('已送到制图师，等待确认'), findsOneWidget);
    expect(
      find.text('Map design draft is ready for review in Cartographer.'),
      findsNothing,
    );
  });
  testWidgets(
    'map completion follows the result protocol even with a stale success status',
    (tester) async {
      for (final result in <Map<String, dynamic>>[
        {'updated': false},
        {'ok': false},
        {'ok': true, 'error': 'failed'},
        {'cancelled': true},
        {'skipped': true},
      ]) {
        final block = AiToolCallBlock(
          id: 'block',
          callId: 'call',
          toolName: 'Run',
          arguments: const {'command': 'map', 'subcommand': 'draft'},
          status: AiToolCallStatus.success,
          result: result,
        );
        await tester.pumpWidget(_wrap(RunToolCardBody(block: block)));
        await tester.pumpAndSettle();
        expect(
          find.text('已送到制图师，等待确认'),
          result.containsKey('updated') ? findsOneWidget : findsNothing,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData(),
        builder: (context, child) => RevericTheme(
          data: RevericThemeData.reveric,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}
