// 职责: 验证模型设置使用独立的桌面提示词编辑面板，不暴露专家其他字段。
// 关联文件:
//   lib/desktop/widgets/agent_management/subagent_prompt_edit_panel.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_studio.json
//   assets/translations/zh-CN/agent_studio.json
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/i18n.md
//   .agents/rules/testing.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/subagent_prompt_edit_panel.dart';
import 'package:reveric/shared/components/reveric_switch.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _writer = SubAgent(
  id: 'writer-1',
  slug: 'writer',
  name: 'Long-form Writing',
  description: 'Writes delegated chapter batches.',
  prompt: 'Default writer prompt',
  scope: SubAgentScope.global,
  sortOrder: 0,
  useCustomPrompt: true,
);

SubAgent? _updatedAgent;

class _TestGlobalSubAgents extends GlobalSubAgents {
  @override
  Future<List<SubAgent>> build() async => const [_writer];

  @override
  Future<void> updateSubAgent(SubAgent agent) async {
    _updatedAgent = agent;
  }
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
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('only prompt settings are editable', (tester) async {
    _updatedAgent = null;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => ProviderScope(
            overrides: [
              appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
              globalSubAgentsProvider.overrideWith(_TestGlobalSubAgents.new),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: Scaffold(
                  body: SubAgentPromptEditPanel(
                    agent: _writer,
                    onBack: () {},
                    onSaved: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsNothing);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Subagent Type'), findsNothing);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Reasoning Effort'), findsNothing);
    expect(find.text('Enabled'), findsNothing);
    expect(find.text('Use custom prompt'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);

    await tester.tap(find.byType(RevericSwitch));
    await tester.pumpAndSettle();

    final saveAfterToggle = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveAfterToggle.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(_updatedAgent?.useCustomPrompt, isFalse);
    expect(_updatedAgent?.prompt, isEmpty);
    expect(_updatedAgent?.name, _writer.name);
    expect(_updatedAgent?.description, _writer.description);
    expect(tester.takeException(), isNull);
  });
}
