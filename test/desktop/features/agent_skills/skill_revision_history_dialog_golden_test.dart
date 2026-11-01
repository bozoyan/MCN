// 职责: AgentSkill 版本历史对话框黄金图（加载真实字体），人工目检布局与可读性（非 CI 断言）。
// 关联文件:
//   lib/desktop/features/agent_skills/skill_revision_history_dialog.dart
//   lib/shared/widgets/agent_skill/skill_revision_components.dart

import 'dart:io';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/agent_skills/skill_revision_history_dialog.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/models/agent_skill_revision.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/providers/agent_skill_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _current = NovelAgentSkillModel(
  id: 'nas_1',
  sourceKind: AgentSkillSourceKind.novelLocal,
  name: '章节审稿',
  whenToUse: '需要对已完成章节做质量复核时调用。',
  description: '按节奏、伏笔、人物一致性三个维度审查章节。',
  prompt: '# 章节审稿\n\n## 目标\n逐段核对节奏与伏笔。\n\n## 步骤\n1. 通读全章\n2. 标注问题\n3. 汇总建议',
);

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
    // AiDiffView 硬编码 'monospace'（系统字体，测试环境缺失）→ 用中文字体代打，
    // 否则 diff 正文全是 tofu，看不出这块 UI 到底长什么样。
    await _loadFont('monospace', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  testWidgets('golden: 版本历史对话框', (tester) async {
    tester.view.physicalSize = const Size(1100, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    await db.novelAgentSkillRevisionDao.appendRevision(
      content: _current.copyWith(
        prompt: '# 章节审稿\n\n## 目标\n逐段核对节奏。\n\n## 步骤\n1. 通读全章\n2. 汇总建议',
      ),
      changeSource: SkillRevisionSource.install,
    );
    await db.novelAgentSkillRevisionDao.appendRevision(
      content: _current.copyWith(
        prompt: '# 章节审稿\n\n## 目标\n逐段核对节奏与伏笔。\n\n## 步骤\n1. 通读全章\n2. 汇总建议',
        references: const [
          AgentSkillReferenceFile(
            path: 'references/rubric.md',
            content: '# 审稿量表',
          ),
        ],
      ),
      changeSource: SkillRevisionSource.ai_edit,
      turnId: 'turn_1',
      changeNote: '补充伏笔维度',
    );

    await tester.pumpWidget(
      _wrap(db, const SkillRevisionHistoryDialog(skill: _current)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SkillRevisionHistoryDialog),
      matchesGoldenFile('goldens/skill_revision_history_dialog.png'),
    );
  });
}

Widget _wrap(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      agentSkillAppDatabaseProvider.overrideWithValue(db),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            // 应用运行时靠系统 CJK 字体兜底；测试环境没有，必须显式指定，
            // 否则中文全渲染成 tofu，目检失去意义。
            theme: RevericThemeData.reveric.toThemeData(
              fontFamily: 'LXGWWenKai',
            ),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(body: Center(child: child)),
            ),
          );
        },
      ),
    ),
  );
}
