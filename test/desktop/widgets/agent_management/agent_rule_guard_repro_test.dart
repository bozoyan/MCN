// 职责: 回归「新建 rule 保存后仍停留在编辑页 / 再次切换仍弹窗」的父级守卫流程。
//   验证父级（会随未保存状态反复 rebuild）能稳定拿到面板注册的保存函数。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_rule_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_rule.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/markdown_editor_test_helper.dart';

final notDeletedSentinel = DateTime.fromMillisecondsSinceEpoch(0);

AgentRule _newRule() {
  final now = DateTime.now();
  return AgentRule(
    id: '__new__${now.microsecondsSinceEpoch}',
    name: '',
    content: '',
    enabled: true,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

/// Mirror of novel_editor.dart's contentSelection / guard wiring, reduced to
/// the agent-rule path.
class _ParentHarness extends HookConsumerWidget {
  const _ParentHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null = workspace (navigated away). non-null = editing this rule.
    final selectedRule = useState<AgentRule?>(_newRule());
    final agentRuleHasChanges = useState(false);
    final activeAgentPanelSave = useRef<Future<bool> Function()?>(null);

    bool hasUnsavedChanges() =>
        selectedRule.value != null && agentRuleHasChanges.value;

    Future<bool> guardUnsavedChanges() async {
      if (!hasUnsavedChanges()) return false;
      // Simulate the dialog's "Save" choice directly.
      final save = activeAgentPanelSave.value;
      final saved = save != null && await save();
      if (!saved) return true; // stay
      agentRuleHasChanges.value = false;
      return false;
    }

    Future<void> navigateAway() async {
      final canSwitch = !(await guardUnsavedChanges());
      if (!canSwitch) return;
      selectedRule.value = null; // showWorkspaceContent()
    }

    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              TextButton(
                key: const Key('navigate'),
                onPressed: navigateAway,
                child: const Text('navigate'),
              ),
              Text(
                key: const Key('state'),
                'rule=${selectedRule.value != null} '
                'dirty=${agentRuleHasChanges.value}',
              ),
            ],
          ),
          Expanded(
            child: selectedRule.value == null
                ? const Center(child: Text('workspace'))
                : AgentRuleEditPanel(
                    rule: selectedRule.value!,
                    databasePath: null,
                    onSaved: () {
                      selectedRule.value = null;
                      agentRuleHasChanges.value = false;
                    },
                    onHasChangesChanged: (v) => agentRuleHasChanges.value = v,
                    onRegisterSave: (save) => activeAgentPanelSave.value = save,
                    onSaveRule: (draft) async =>
                        draft.toRule(updatedAt: DateTime.now()),
                    onRuleSaved: (savedRule) {
                      selectedRule.value = savedRule;
                      agentRuleHasChanges.value = false;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('new rule: edit then guard-save navigates away and stays clean', (
    tester,
  ) async {
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
                  child: const _ParentHarness(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fill name + content so validation passes.
    await tester.enterText(find.byType(TextField).first, 'My Rule');
    await enterMarkdownEditorText(tester, 'Hello world');

    expect(
      find.textContaining('dirty=true'),
      findsOneWidget,
      reason: 'editing should mark dirty',
    );
    await tester.tap(find.byKey(const Key('navigate')));
    await tester.pumpAndSettle();

    expect(
      find.text('workspace'),
      findsOneWidget,
      reason: 'after guard-save the page must navigate away',
    );
  });
}
