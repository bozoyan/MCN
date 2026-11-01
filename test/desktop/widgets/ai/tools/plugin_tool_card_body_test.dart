// 职责: 验证插件展示快照及插件化前 Web 历史在共享卡片和详情中保留预览。
// 关联文件:
//   lib/shared/widgets/ai/tools/plugin_tool_card_body.dart
//   lib/shared/widgets/ai/tools/tool_detail_body.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_detail_body.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_card_descriptor.dart';
import 'package:reveric/shared/widgets/ai/tools/plugin_tool_card_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  testWidgets(
    'saved plugin metadata renders custom title, summary and items without a host',
    (tester) async {
      const original = AiToolCallBlock(
        id: 'block',
        callId: 'call',
        toolName: 'SearchCustom',
        arguments: {'term': 'query'},
        status: AiToolCallStatus.success,
        metadata: {
          'tool_source': 'plugin',
          'plugin_name': 'Saved plugin',
          'plugin_id': 'example.search',
          'plugin_display': {
            'title': 'Custom search',
            'summaryArg': 'term',
            'result': 'items',
            'resultPath': 'items',
          },
        },
        result: {
          'items': [
            {'title': 'First', 'snippet': 'Readable snippet'},
            {'url': 'https://example.com'},
          ],
        },
      );
      final block = AiToolCallBlock.fromJson(original.toJson());
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Column(
              children: [
                Text(toolActionVerb(context, block)),
                aiToolBodyFor(context, block)!,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PluginToolCardBody), findsOneWidget);
      expect(find.text('Custom search'), findsOneWidget);
      expect(find.text('query'), findsOneWidget);
      expect(find.text('Saved plugin'), findsOneWidget);
      expect(find.textContaining('Readable snippet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('legacy Web history keeps item and text previews', (
    tester,
  ) async {
    const search = AiToolCallBlock(
      id: 'old-search',
      callId: 's',
      toolName: 'WebSearch',
      arguments: {'query': 'old query'},
      result: {
        'results': [
          {'title': 'Old result', 'snippet': 'Old snippet'},
        ],
      },
    );
    const fetch = AiToolCallBlock(
      id: 'old-fetch',
      callId: 'f',
      toolName: 'WebFetch',
      arguments: {'url': 'https://example.com'},
      result: {'markdown': 'Historical markdown'},
    );
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Column(
            children: [
              aiToolBodyFor(context, search)!,
              aiToolBodyFor(context, fetch)!,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('old query'), findsOneWidget);
    expect(find.textContaining('Old snippet'), findsOneWidget);
    expect(find.text('Historical markdown'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Widget _wrap(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  child: Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: RevericThemeData.reveric.toThemeData(),
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(body: child),
      ),
    ),
  ),
);
