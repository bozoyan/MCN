// 职责: 回归 AgentRule 编辑面板输入首字符后不应失焦。
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

class _ParentHarness extends HookConsumerWidget {
  const _ParentHarness({required this.rule});

  final AgentRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentRuleHasChanges = useState(false);

    return Scaffold(
      body: Column(
        children: [
          Text('dirty=${agentRuleHasChanges.value}'),
          Expanded(
            child: AgentRuleEditPanel(
              rule: rule,
              databasePath: null,
              onSaved: () {},
              onCancel: () {},
              onHasChangesChanged: (v) => agentRuleHasChanges.value = v,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _pumpHarness(WidgetTester tester, AgentRule rule) async {
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
                child: _ParentHarness(rule: rule),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('name field keeps focus during IME composing and after commit', (
    tester,
  ) async {
    await _pumpHarness(tester, _newRule());

    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    final focusBefore = FocusManager.instance.primaryFocus;
    expect(focusBefore, isNotNull);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'n',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus,
      focusBefore,
      reason:
          'IME composing must not rebuild away focus on first pinyin letter',
    );

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus,
      focusBefore,
      reason:
          'IME commit must not rebuild away focus when dirty state flips true',
    );
    expect(find.text('dirty=true'), findsOneWidget);
  });
}
