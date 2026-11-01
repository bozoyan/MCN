// 职责: 验证本地智能体技能编辑面板展示可折叠 references 层级、子目录新增文件并按所选类别保存。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_edit_panel.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/providers/dictionary_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/en/common.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/agent_skills/setup_edit_panel.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/providers/dictionary_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  patrolWidgetTest(
    'keeps the selected category after parent dirty-state rebuild and saves it',
    ($) async {
      final tester = $.tester;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AgentSkillSetupEditDraft? saved;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skillCategoriesProvider.overrideWith(
              (ref) async => const ['润色', '结构'],
            ),
            skillTagsProvider.overrideWith((ref) async => const []),
          ],
          child: EasyLocalization(
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
                  home: Scaffold(
                    body: RevericTheme(
                      data: RevericThemeData.reveric,
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          return AgentSkillSetupEditPanel(
                            draft: AgentSkillSetupEditDraft(
                              name: 'Local Skill',
                              whenToUse: 'when needed',
                              description: 'description',
                              prompt: 'prompt',
                              category: '润色',
                              references: const [
                                AgentSkillReferenceFile(
                                  path: 'references/planning/continuity.md',
                                  content: 'Keep the setting consistent.',
                                ),
                                AgentSkillReferenceFile(
                                  path: 'references/style.md',
                                  content: 'Keep the prose concise.',
                                ),
                              ],
                              enabled: true,
                            ),
                            createTitleKey: LocaleKeys.commonCreate,
                            onBack: () {},
                            onHasChangesChanged: (_) => setState(() {}),
                            onSave: (draft) async {
                              saved = draft;
                              return draft;
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AgentSkillReferences.relativeDir), findsOneWidget);
      expect(find.text('planning'), findsOneWidget);
      expect(find.text('continuity.md'), findsOneWidget);
      expect(find.text('style.md'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(tr(LocaleKeys.agentSkillReferencesAdd)),
          matching: find.byType(ListView),
        ),
        findsNWidgets(2),
      );
      expect(
        tester
            .getTopLeft(find.text(tr(LocaleKeys.agentSkillReferencesAdd)).last)
            .dy,
        greaterThan(tester.getTopLeft(find.text('style.md')).dy),
      );

      await tester.tap(find.text('continuity.md'));
      await tester.pumpAndSettle();
      expect(find.byType(RevericTextField), findsNWidgets(2));

      await tester.tap(find.text(tr(LocaleKeys.agentSkillMainDocument)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RevericSelect<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('结构'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(tr(LocaleKeys.commonSave)));
      await tester.pumpAndSettle();

      expect(saved?.category, '结构');

      await tester.tap(find.text('planning'));
      await tester.pumpAndSettle();
      expect(find.text('continuity.md'), findsNothing);
      expect(find.text('style.md'), findsOneWidget);

      await tester.tap(find.text('planning'));
      await tester.pumpAndSettle();
      expect(find.text('continuity.md'), findsOneWidget);

      await tester.tap(find.text(tr(LocaleKeys.agentSkillReferencesAdd)).first);
      await tester.pumpAndSettle();
      expect(find.text('ref-3.md'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
