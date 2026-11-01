// 职责: 测试上下文压缩事件行的收起信息与展开摘要行为。
// 关联文件:
//   lib/shared/widgets/ai/chat/compaction_card.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/compaction_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  testWidgets('keeps compaction low-priority until its summary is requested', (
    tester,
  ) async {
    await _pumpWrapped(
      tester,
      const CompactionCard(
        summary:
            '## Current task\n'
            'The prior turns established the **chapter order**.',
        metadata: {'tokens_before': 30600, 'tokens_after': 2600},
      ),
    );

    expect(find.text('Context organized'), findsOneWidget);
    expect(find.text('31k → 3k'), findsOneWidget);
    expect(
      find.textContaining('chapter order', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.text('Context organized'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('chapter order', findRichText: true),
      findsWidgets,
    );
    // 摘要是 Markdown，展开后不能露出原始标记。
    expect(find.textContaining('##', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
  });
}

Future<void> _pumpWrapped(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    EasyLocalization(
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
              child: Scaffold(body: Center(child: child)),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
