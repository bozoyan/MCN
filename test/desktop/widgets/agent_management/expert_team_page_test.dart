// 职责: 验证专家团内置 tab 在渲染内置讨论专家时不发生无界高度布局错误。
// 关联文件:
//   lib/desktop/widgets/agent_management/expert_team_page.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_studio.json
//   assets/translations/zh-CN/agent_studio.json
//   assets/translations/en/subagent.json
//   assets/translations/zh-CN/subagent.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/expert_team_page.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<SubAgent> _officialExperts = [
  SubAgent(
    id: 'expert-1',
    slug: 'plot_architect',
    name: 'Plot Architect',
    description: 'Plans story structure.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 0,
  ),
  SubAgent(
    id: 'expert-2',
    slug: 'character_analyst',
    name: 'Character Analyst',
    description: 'Reviews character arcs.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 1,
  ),
  SubAgent(
    id: 'expert-3',
    slug: 'world_builder',
    name: 'World Builder',
    description: 'Maintains world consistency.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 2,
  ),
  SubAgent(
    id: 'expert-4',
    slug: 'pacing_expert',
    name: 'Pacing Expert',
    description: 'Evaluates story pacing.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 3,
  ),
  SubAgent(
    id: 'expert-5',
    slug: 'conflict_designer',
    name: 'Conflict Designer',
    description: 'Designs dramatic conflict.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 4,
  ),
  SubAgent(
    id: 'expert-6',
    slug: 'theme_guardian',
    name: 'Theme Guardian',
    description: 'Checks thematic consistency.',
    prompt: '',
    mode: 'council',
    scope: SubAgentScope.global,
    sortOrder: 5,
  ),
];

class _TestGlobalSubAgents extends GlobalSubAgents {
  @override
  Future<List<SubAgent>> build() async => _officialExperts;
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

  testWidgets('built-in experts render after switching tabs', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('zh', 'CN'),
        startLocale: const Locale('zh', 'CN'),
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
                  body: AgentExpertTeamPage(
                    headerGestureExclusionKey: GlobalKey(),
                    onOpen: (_) {},
                    onCreate: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('内置子智能体'));
    await tester.pumpAndSettle();

    for (final expert in _officialExperts) {
      expect(find.text(expert.name), findsOneWidget);
    }
    expect(find.text('讨论型子智能体'), findsNWidgets(_officialExperts.length + 1));

    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('重置为默认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
