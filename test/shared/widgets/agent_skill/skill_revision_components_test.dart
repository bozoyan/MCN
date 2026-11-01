// 职责: 验证版本历史组件在真实 i18n 上下文下渲染列表与详情 diff。
// 关联文件:
//   lib/shared/widgets/agent_skill/skill_revision_components.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/agent_skill_revision.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/design-system.md
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/models/agent_skill_revision.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/providers/agent_skill_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/agent_skill/skill_revision_components.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _skill = NovelAgentSkillModel(
  id: 'nas_1',
  sourceKind: AgentSkillSourceKind.novelLocal,
  name: '章节审稿',
  description: 'desc',
  prompt: '当前指令\n第二行',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('列表渲染版本项，详情渲染 diff 与附件', (tester) async {
    final db = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    await db.novelAgentSkillRevisionDao.appendRevision(
      content: _skill.copyWith(
        prompt: '旧指令\n第二行',
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: '附件正文'),
        ],
      ),
      changeSource: SkillRevisionSource.ai_edit,
    );
    final summaries = await db.novelAgentSkillRevisionDao.listRevisions(
      'nas_1',
    );
    expect(summaries, hasLength(1));

    // 同一个 test 内连续 pump 两棵树：EasyLocalization 在第二个 testWidgets
    // 里重包会得到空子树。
    await tester.pumpWidget(
      _wrap(
        db,
        SkillRevisionList(
          revisions: summaries,
          selectedId: summaries.single.id,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('v1'), findsOneWidget);
    expect(find.text('Edited by AI'), findsOneWidget);
    expect(find.text('Current version'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        db,
        SkillRevisionDetailView(
          revisionId: summaries.single.id,
          current: _skill,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Copy instructions'), findsOneWidget);
    expect(find.text('references/a.md'), findsOneWidget);
    expect(find.text('Copy file'), findsOneWidget);
    // prompt 与当前不同 → 展示 diff，而不是「与当前版本相同」。
    expect(find.text('Instructions match the current version'), findsNothing);
  });
}

Widget _wrap(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      agentSkillAppDatabaseProvider.overrideWithValue(db),
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
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(body: child),
            ),
          );
        },
      ),
    ),
  );
}
