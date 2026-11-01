// 职责: 回归已有 rule 未保存时点 + 应弹窗，空白新建草稿点 + 直接放弃。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/agent_rule_edit_panel.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_rule.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/unsaved_changes_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _notDeletedSentinel = DateTime.fromMillisecondsSinceEpoch(0);

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
    deletedAt: _notDeletedSentinel,
  );
}

AgentRule _existingRule() {
  final now = DateTime.now();
  return AgentRule(
    id: 'rule-a',
    name: 'Existing Rule',
    content: 'baseline content',
    enabled: true,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: _notDeletedSentinel,
  );
}

class _Harness extends HookConsumerWidget {
  const _Harness({required this.initialRule});

  final AgentRule initialRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRule = useState<AgentRule?>(initialRule);
    final agentRuleHasChanges = useState(false);
    final activeAgentPanelSave = useRef<Future<bool> Function()?>(null);
    final activeAgentPanelHasChanges = useRef<bool Function()?>(null);
    final activeAgentPanelIsBlankCreateDraft = useRef<bool Function()?>(null);
    final savedRules = useState(<AgentRule>[]);
    final dialogCount = useState(0);

    Future<bool> guardUnsavedChanges() async {
      if (activeAgentPanelIsBlankCreateDraft.value?.call() ?? false) {
        agentRuleHasChanges.value = false;
        return false;
      }
      final hasChanges =
          activeAgentPanelHasChanges.value?.call() ?? agentRuleHasChanges.value;
      if (!hasChanges) {
        return false;
      }
      dialogCount.value++;
      final decision = await showUnsavedChangesDialog(
        context: context,
        titleKey: LocaleKeys.editorUnsavedChangesTitle,
        messageKey: LocaleKeys.editorUnsavedChangesMessage,
      );
      switch (decision) {
        case null:
          return true;
        case UnsavedChangesDecision.discard:
          agentRuleHasChanges.value = false;
          return false;
        case UnsavedChangesDecision.save:
          final save = activeAgentPanelSave.value;
          final saved = save != null && await save();
          if (!saved) {
            return true;
          }
          agentRuleHasChanges.value = false;
          return false;
      }
    }

    Future<void> createNewRule() async {
      final newRule = _newRule();
      final canSwitch = !(await guardUnsavedChanges());
      if (!canSwitch) {
        return;
      }
      selectedRule.value = newRule;
    }

    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const Key('create'),
            onPressed: createNewRule,
            child: const Text('create'),
          ),
          Text(
            key: const Key('state'),
            'rule=${selectedRule.value?.id ?? 'none'} '
            'dirty=${agentRuleHasChanges.value}',
          ),
          Text(
            key: const Key('saved-state'),
            'saved=${savedRules.value.length} '
            'last=${savedRules.value.isEmpty ? 'none' : savedRules.value.last.name}',
          ),
          Text(key: const Key('dialog-count'), 'dialogs=${dialogCount.value}'),
          Expanded(
            child: AgentRuleEditPanel(
              rule: selectedRule.value!,
              databasePath: null,
              onSaved: () {},
              onHasChangesChanged: (v) => agentRuleHasChanges.value = v,
              onRegisterSave: (save) => activeAgentPanelSave.value = save,
              onRegisterHasChanges: (hasChanges) =>
                  activeAgentPanelHasChanges.value = hasChanges,
              onRegisterIsBlankCreateDraft: (isBlank) =>
                  activeAgentPanelIsBlankCreateDraft.value = isBlank,
              onSaveRule: (draft) async {
                final savedRule = draft.toRule(updatedAt: DateTime.now());
                savedRules.value = [...savedRules.value, savedRule];
                return savedRule;
              },
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

  testWidgets(
    '+ create prompts for dirty rule and skips prompt for empty new draft',
    (tester) async {
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
                    child: _Harness(initialRule: _existingRule()),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RevericTextField), findsOneWidget);
      await tester.enterText(find.byType(RevericTextField), 'Edited name');
      await tester.pumpAndSettle();

      expect(find.textContaining('dirty=true'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('dialogs=1'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('saved=1 last=Edited name'),
        findsOneWidget,
        reason: 'Save in the + dialog must persist edits before switching',
      );
      expect(
        find.textContaining('rule=__new__'),
        findsOneWidget,
        reason: 'must switch to the new draft rule after auto-save',
      );
      expect(
        find.textContaining('dirty=false'),
        findsOneWidget,
        reason: 'new draft must start clean',
      );

      final nameController = tester
          .widget<RevericTextField>(find.byType(RevericTextField))
          .controller;
      expect(
        nameController?.text,
        isEmpty,
        reason:
            'new rule form must show empty name immediately, not prior rule',
      );

      await tester.tap(find.byKey(const Key('create')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('dialogs=1'),
        findsOneWidget,
        reason: 'empty new draft should be discarded without a dialog',
      );
      expect(find.textContaining('saved=1 last=Edited name'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'Second rule');
      await tester.enterText(fields.last, 'Second content');
      await tester.pumpAndSettle();

      expect(find.textContaining('dirty=true'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('dialogs=2'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Discard'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('saved=1 last=Edited name'),
        findsOneWidget,
        reason: 'Discard in the + dialog must not save the second draft',
      );
      expect(find.textContaining('dirty=false'), findsOneWidget);
    },
  );
}
