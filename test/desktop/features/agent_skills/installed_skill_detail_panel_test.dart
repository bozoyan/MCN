// 职责: 验证已安装技能详情页收敛重复名称展示。
// 关联文件:
//   lib/desktop/features/agent_skills/installed_skill_detail_panel.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/agent_skills/installed_skill_detail_panel.dart';
import 'package:reveric/desktop/features/agent_skills/source_card.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _skillName = 'AI Glossary Maintenance';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('removes redundant name chips and prompt heading', (
    tester,
  ) async {
    const skill = NovelAgentSkillModel(
      id: 'skill-1',
      sourceKind: AgentSkillSourceKind.marketplace,
      name: _skillName,
      description: 'Maintains the novel AI glossary.',
      prompt: '# $_skillName\n\n## Goal\n\nKeep terms consistent.',
    );

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: Scaffold(
                  body: InstalledSkillDetailPanel(
                    skill: skill,
                    onBack: () {},
                    onEdit: () {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentSkillSourceTag), findsNothing);
    // 编辑入口：官方/市场技能可编辑，改写即脱离来源。
    expect(find.text('Edit'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == _skillName,
      ),
      findsNWidgets(2),
      reason: 'the name belongs in navigation and the detail hero only',
    );
  });
}
