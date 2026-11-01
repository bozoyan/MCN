// 职责: 验证 AgentSkill references 文件树 — 嵌套目录可展开/收起，且只读模式
//   不显示新增入口，选择文件仍能通知调用方展示只读预览。
// 关联文件:
//   lib/desktop/features/agent_skills/agent_skill_reference_file_tree.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/agent_skills/agent_skill_reference_file_tree.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'reference tree collapses nested directories and selects files in read-only mode',
    (tester) async {
      var selectedReference = -1;

      await tester.pumpWidget(
        _wrap(
          AgentSkillReferenceFileTree(
            references: const [
              AgentSkillReferenceFile(
                path: 'references/genre-styles/revenge.md',
                content: 'revenge guide',
              ),
              AgentSkillReferenceFile(
                path: 'references/outline.md',
                content: 'outline guide',
              ),
            ],
            selectedIndex: -1,
            readOnly: true,
            onSelectMain: () {},
            onSelectReference: (index) => selectedReference = index,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('genre-styles'), findsOneWidget);
      expect(find.text('revenge.md'), findsOneWidget);
      expect(find.text(tr(LocaleKeys.agentSkillReferencesAdd)), findsNothing);

      await tester.tap(find.text('genre-styles'));
      await tester.pumpAndSettle();
      expect(find.text('revenge.md'), findsNothing);

      await tester.tap(find.text('genre-styles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('revenge.md'));
      expect(selectedReference, 0);
    },
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: RevericThemeData.reveric,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}
