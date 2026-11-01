// 职责: 复现新建 AgentRule 保存后误报「未保存变更」的问题。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_rule_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_rule.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/markdown_editor_test_helper.dart';

AgentRule _rule({
  required String id,
  required String name,
  required String content,
  required int updatedAtMs,
}) {
  return AgentRule(
    id: id,
    name: name,
    content: content,
    enabled: true,
    sortOrder: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.onChanges,
    this.onRegisterSave,
    this.onRuleSaved,
  });

  final ValueChanged<bool> onChanges;
  final ValueChanged<Future<bool> Function()?>? onRegisterSave;
  final ValueChanged<AgentRule>? onRuleSaved;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  // Start as a freshly-created rule (empty draft), like newAgentRuleDraft().
  AgentRule rule = _rule(id: '__new__1', name: '', content: '', updatedAtMs: 1);

  void simulateSaveReselect() {
    // After save the rule keeps the SAME temp id but gets filled content +
    // a new updatedAt, and the selection re-resolves to it.
    setState(() {
      rule = _rule(
        id: '__new__1',
        name: 'My Rule',
        content: 'Hello world',
        updatedAtMs: 2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AgentRuleEditPanel(
      rule: rule,
      databasePath: null,
      onSaved: () {},
      onHasChangesChanged: widget.onChanges,
      onRegisterSave: widget.onRegisterSave,
      onRuleSaved: widget.onRuleSaved,
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('new rule stays clean after save re-renders with saved content', (
    tester,
  ) async {
    final changes = <bool>[];
    final savedRules = <AgentRule>[];
    Future<bool> Function()? registeredSave;
    final key = GlobalKey<_HarnessState>();

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
                    body: _Harness(
                      key: key,
                      onChanges: changes.add,
                      onRegisterSave: (save) => registeredSave = save,
                      onRuleSaved: savedRules.add,
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

    // User types content, making the panel dirty.
    await enterMarkdownEditorText(tester, 'Hello world');
    expect(changes.last, isTrue, reason: 'typing should mark dirty: $changes');

    // Save re-renders the panel with the saved rule: same (temp) id, filled
    // content, new updatedAt. The form must rebuild and clear hasChanged,
    // otherwise the panel keeps reporting unsaved changes forever.
    key.currentState!.simulateSaveReselect();
    await tester.pumpAndSettle();

    expect(
      changes.last,
      isFalse,
      reason:
          'after save the saved content matches the rule, so the panel must '
          'not report unsaved changes: $changes',
    );

    await enterMarkdownEditorText(tester, 'Hello world updated');

    expect(changes.last, isTrue, reason: 'editing should mark dirty: $changes');
    expect(registeredSave, isNotNull);
    expect(await registeredSave!(), isTrue);
    await tester.pumpAndSettle();

    expect(savedRules.last.content, 'Hello world updated');
    expect(
      changes.last,
      isFalse,
      reason: 'dialog save path must clear dirty without parent reselect',
    );
  });
}
