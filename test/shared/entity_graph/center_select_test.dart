// 职责: 实体关系图中心点选择测试 — 验证 RevericSelect 能切换中心实体。
// 关联文件:
//   lib/shared/entity_graph/center_select.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/character.json
//   assets/translations/zh-CN/character.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/entity_graph/entity_graph.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'opens RevericSelect and changes graph center',
    (tester) async {
      var centerKey = 'character_a';

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return EntityGraphCenterSelect(
                centerKey: centerKey,
                candidateKeys: const ['character_a', 'character_b'],
                nameMap: const {'character_a': 'Aster', 'character_b': 'Zhou'},
                typeNameMap: const {
                  'character_a': characterRoleProtagonist,
                  'character_b': characterRoleSupporting,
                },
                onChanged: (next) => setState(() => centerKey = next),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RevericSelect<String>), findsOneWidget);
      expect(find.text('Aster'), findsOneWidget);
      expect(find.text('Zhou'), findsNothing);

      await tester.tap(find.byType(RevericSelect<String>));
      await tester.pumpAndSettle();

      expect(find.text('Zhou'), findsOneWidget);

      await tester.tap(find.text('Zhou'));
      await tester.pumpAndSettle();

      expect(centerKey, 'character_b');
      expect(find.text('Zhou'), findsOneWidget);
      expect(find.text('Aster'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
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
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
