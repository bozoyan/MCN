// 职责: 验证 AgentRuleEditPanel 通过 onRegisterSave 暴露的保存函数行为。
//   保存只持久化、返回是否成功，且不触发导航（onSaved）。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_edit_save_contract.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_rule_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_rule.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/markdown_editor_test_helper.dart';

AgentRule _rule({required String name, required String content}) {
  return AgentRule(
    id: 'rule-1',
    name: name,
    content: content,
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

  testWidgets('registered save reports success and does not navigate', (
    tester,
  ) async {
    Future<bool> Function()? registeredSave;
    AgentRuleEditDraft? savedDraft;
    var savedNavCount = 0;
    var savedEntityCount = 0;

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
                      // Already-valid rule so save() validates without fragile
                      // markdown-editor text entry.
                      rule: _rule(name: 'My Rule', content: 'Body content'),
                      databasePath: null,
                      onSaved: () => savedNavCount++,
                      onRegisterSave: (fn) => registeredSave = fn,
                      onSaveRule: (draft) async {
                        savedDraft = draft;
                        return draft.toRule(updatedAt: DateTime(2026));
                      },
                      onRuleSaved: (_) => savedEntityCount++,
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

    expect(registeredSave, isNotNull, reason: 'panel must register its save');

    final longContent = List.filled(
      agentRuleLongContentWarningThreshold + 1,
      'x',
    ).join();
    await enterMarkdownEditorText(tester, longContent);

    // A long rule requires an explicit confirmation before it reaches the
    // page-level saver, so the warning remains visible when the panel closes.
    final saveResult = registeredSave!();
    await tester.pumpAndSettle();

    expect(savedDraft, isNull);
    expect(
      find.text(
        'This rule is loaded into every conversation. At more than '
        '$agentRuleLongContentWarningThreshold characters, it uses a '
        'significant amount of model context. Move the detailed instructions '
        'into an agent skill, then state in this rule when that skill must be '
        'used.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await saveResult, isTrue);
    expect(savedDraft?.content, longContent);
    expect(savedEntityCount, 1);
    expect(savedNavCount, 0, reason: 'registered save must not navigate');
  });
}
