// 职责: 验证专家编辑页隐藏内部标识符后，文本编辑仍会正确启用保存。
// 关联文件:
//   lib/desktop/widgets/agent_management/subagent_edit_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/i18n.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/subagent_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

SubAgent _customAgent({
  required String name,
  required String description,
  required String prompt,
}) {
  return SubAgent(
    id: 'subagent-custom-1',
    slug: 'fdf',
    name: name,
    description: description,
    prompt: prompt,
    scope: SubAgentScope.global,
    sortOrder: 0,
    useCustomPrompt: true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

class _EmptyGlobalSubAgents extends GlobalSubAgents {
  @override
  Future<List<SubAgent>> build() async => const [];
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'en',
      aiSettings: AiSettings.defaults(),
    );
  }
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'custom subagent text edit enables Save (no default prompt path)',
    (tester) async {
      final changes = <bool>[];

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
                overrides: [
                  appSettingsProvider.overrideWith(
                    _TestAppSettingsNotifier.new,
                  ),
                  globalSubAgentsProvider.overrideWith(
                    _EmptyGlobalSubAgents.new,
                  ),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  theme: RevericThemeData.reveric.toThemeData(),
                  home: RevericTheme(
                    data: RevericThemeData.reveric,
                    child: Scaffold(
                      body: SubAgentEditPanel(
                        agent: _customAgent(
                          name: 'fdf',
                          description: 'fdfd',
                          prompt: 'old prompt',
                        ),
                        onSaved: () {},
                        onHasChangesChanged: changes.add,
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

      expect(find.text('Slug'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull, reason: 'baseline must start clean');

      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'fdf updated');
      await tester.pumpAndSettle();

      expect(
        changes.where((c) => c).isNotEmpty,
        isTrue,
        reason: 'typing must mark dirty for custom agents: $changes',
      );

      final saveAfterEdit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(
        saveAfterEdit.onPressed,
        isNotNull,
        reason:
            'Save must enable after text edits on custom agents without '
            'builtin default prompts',
      );
    },
  );
}
