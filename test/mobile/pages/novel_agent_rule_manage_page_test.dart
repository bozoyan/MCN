// 职责: 回归移动端跨作品复制智能体规则 — 入口、来源选择、同名跳过与目标库写入。
// 关联文件:
//   lib/mobile/pages/novel_agent_rule_manage_page.dart
//   lib/mobile/widgets/agent_rule_copy_sheet.dart
//   lib/shared/services/agent_rule_copy_service.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/pages/novel_agent_rule_manage_page.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _targetPath = 'mobile-agent-rule-copy-target';
const _sourcePath = 'mobile-agent-rule-copy-source';
const _emptySourcePath = 'mobile-agent-rule-copy-empty-source';

AgentRule _rule(String id, String name, String content, {int sortOrder = 0}) {
  final now = DateTime.now();
  return AgentRule(
    id: id,
    name: name,
    content: content,
    enabled: true,
    sortOrder: sortOrder,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Novel _novel(String id, String title, String? databasePath) {
  final now = DateTime.now();
  return Novel(
    id: id,
    title: title,
    authorName: '作者',
    description: '',
    status: 'ongoing',
    type: 'original',
    contentKind: contentKindNovel,
    contentDatabasePath: databasePath,
    wordCount: 0,
    draft: false,
    category: '玄幻',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('copies rules from another novel on mobile', (tester) async {
    final targetDatabase = NovelContentDatabase.forTest(
      NativeDatabase.memory(),
    );
    final sourceDatabase = NovelContentDatabase.forTest(
      NativeDatabase.memory(),
    );
    final emptySourceDatabase = NovelContentDatabase.forTest(
      NativeDatabase.memory(),
    );
    final targetService = NovelContentService(targetDatabase);
    final sourceService = NovelContentService(sourceDatabase);
    final emptySourceService = NovelContentService(emptySourceDatabase);
    addTearDown(targetDatabase.close);
    addTearDown(sourceDatabase.close);
    addTearDown(emptySourceDatabase.close);

    await targetService.upsertAgentRule(
      _rule('target-1', '写作风格', '保持轻松幽默的叙事风格。'),
    );
    await sourceService.upsertAgentRule(
      _rule('source-1', '写作风格', '来源作品的同名规则。'),
    );
    await sourceService.upsertAgentRule(
      _rule('source-2', '视角约束', '全程第三人称限知视角。', sortOrder: 1),
    );
    await sourceService.upsertAgentRule(
      _rule('source-3', '禁用词', '不要出现现代网络流行语。', sortOrder: 2),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelContentServiceProvider(
            _targetPath,
          ).overrideWithValue(targetService),
          novelContentServiceProvider(
            _sourcePath,
          ).overrideWithValue(sourceService),
          novelContentServiceProvider(
            _emptySourcePath,
          ).overrideWithValue(emptySourceService),
          novelsProvider.overrideWith(
            (ref) => Stream.value([
              _novel('novel-target', '当前作品', _targetPath),
              _novel('novel-source', '参考作品', _sourcePath),
              _novel('novel-empty-source', '空规则作品', _emptySourcePath),
              _novel('novel-empty', '无内容库作品', null),
            ]),
          ),
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
                theme: RevericThemeData.reveric.toThemeData(),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: MobileNovelAgentRuleManagePage(
                      novel: _novel('novel-target', '当前作品', _targetPath),
                      databasePath: _targetPath,
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

    await tester.tap(
      find.byKey(const ValueKey('mobile_manage_secondary_action')),
    );
    await tester.pumpAndSettle();

    expect(find.text('从其他作品复制'), findsOneWidget);
    expect(find.text('当前作品'), findsNothing);
    expect(find.text('无内容库作品'), findsNothing);

    await tester.tap(find.text('空规则作品'));
    await tester.pumpAndSettle();
    expect(find.text('该作品暂无智能体规则'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_agent_rule_copy_back_to_sources')),
    );
    await tester.pumpAndSettle();
    expect(find.text('空规则作品'), findsOneWidget);

    await tester.tap(find.text('参考作品'));
    await tester.pumpAndSettle();
    expect(find.text('已存在'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制 2 条'));
    await tester.pumpAndSettle();

    expect(find.text('从其他作品复制'), findsNothing);
    final copied = await targetService.getAgentRules();
    expect(copied.map((rule) => rule.name).toList(), ['写作风格', '视角约束', '禁用词']);
    expect(copied.map((rule) => rule.id), isNot(contains('source-2')));

    await tester.tap(
      find.byKey(const ValueKey('mobile_manage_secondary_action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_agent_rule_copy_close')),
    );
    await tester.pumpAndSettle();
    expect(find.text('从其他作品复制'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
