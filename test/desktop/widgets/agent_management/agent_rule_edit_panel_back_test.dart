// 职责: 验证 AgentRule 编辑器在标题栏提供唯一标题与返回规则列表入口。
// 关联文件:
//   lib/desktop/widgets/agent_management/agent_rule_edit_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_rule_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_rule.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AgentRule _rule() {
  return AgentRule(
    id: 'rule-1',
    name: 'My Rule',
    content: 'Body content',
    enabled: true,
    sortOrder: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('header back button invokes the parent navigation callback', (
    tester,
  ) async {
    var didGoBack = false;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: RevericThemeData.reveric.toThemeData(),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: AgentRuleEditPanel(
                      rule: _rule(),
                      databasePath: null,
                      onSaved: () {},
                      onBack: () => didGoBack = true,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'My Rule',
      ),
      findsOneWidget,
      reason: 'the rule title belongs only in the navigation header',
    );
    await tester.tap(find.byKey(const Key('agent_rule_edit_back')));

    expect(
      didGoBack,
      isTrue,
      reason: 'the editor must offer a direct path back to the rule list',
    );
  });
}
