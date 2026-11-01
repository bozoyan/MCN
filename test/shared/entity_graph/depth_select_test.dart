// 职责: 实体关系图层数选择测试 — 验证工具栏使用 RevericSelect 且能切换 1–5 层。
// 关联文件:
//   lib/shared/entity_graph/depth_select.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_select.dart';
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
    'opens RevericSelect and changes display depth',
    (tester) async {
      var depth = 3;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return EntityGraphDepthSelect(
                depth: depth,
                onChanged: (next) => setState(() => depth = next),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RevericSelect<int>), findsOneWidget);
      expect(find.text('3 Layers'), findsOneWidget);
      expect(find.text('1 Layers'), findsNothing);

      await tester.tap(find.byType(RevericSelect<int>));
      await tester.pumpAndSettle();

      expect(find.text('1 Layers'), findsOneWidget);
      expect(find.text('5 Layers'), findsOneWidget);

      await tester.tap(find.text('1 Layers'));
      await tester.pumpAndSettle();

      expect(depth, 1);
      expect(find.text('1 Layers'), findsOneWidget);
      expect(find.text('5 Layers'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Chinese depth labels use a compact trigger width',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntityGraphDepthSelect(depth: 3, onChanged: (_) {}),
          locale: const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3层'), findsOneWidget);
      expect(
        tester.getSize(find.byType(EntityGraphDepthSelect)).width,
        lessThan(110),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: locale,
    startLocale: locale,
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
