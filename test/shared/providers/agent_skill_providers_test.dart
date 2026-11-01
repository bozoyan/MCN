// 职责: AgentSkill Provider 回归测试 — 验证 chat slash 已安装技能筛选与实时刷新。
// 关联文件:
//   lib/shared/providers/agent_skill_providers.dart
//   lib/shared/models/agent_skill.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/agent_skill.dart';
import 'package:reveric/shared/providers/agent_skill_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadChatSlashSkills', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTest(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('maps executable installed novel skills', () async {
      final now = DateTime.now();
      await db.novelAgentSkillDao.upsert(
        NovelAgentSkillsCompanion.insert(
          id: 'nas_custom',
          sourceKind: agentSkillSourceKindNovelLocal,
          name: 'custom_slash',
          description: 'desc',
          prompt: 'prompt',
          sortOrder: const Value(0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final skills = await loadChatSlashSkills(db: db);
      expect(skills.map((s) => s.name), contains('custom_slash'));
      expect(skills, hasLength(1));
    });

    test(
      'does not expose packaged bundled skills when nothing is installed',
      () async {
        final skills = await loadChatSlashSkills(db: db);
        expect(skills, isEmpty);
      },
    );
  });

  test(
    'chatSlashSkillsProvider refreshes after an installed skill is persisted',
    () async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [agentSkillAppDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final initialLoad = Completer<List<SkillDefinition>>();
      final refreshed = Completer<List<SkillDefinition>>();
      final subscription = container.listen(chatSlashSkillsProvider, (
        previous,
        next,
      ) {
        final skills = next.asData?.value;
        if (skills == null) {
          return;
        }
        if (!initialLoad.isCompleted) {
          initialLoad.complete(skills);
        }
        if (skills.any((skill) => skill.name == 'my_skill') &&
            !refreshed.isCompleted) {
          refreshed.complete(skills);
        }
      });
      addTearDown(subscription.close);

      final initial = await initialLoad.future.timeout(
        const Duration(seconds: 2),
      );
      expect(initial.map((skill) => skill.name), isNot(contains('my_skill')));

      final now = DateTime.now();
      await db.novelAgentSkillDao.upsert(
        NovelAgentSkillsCompanion.insert(
          id: 'nas_my_skill',
          sourceKind: agentSkillSourceKindNovelLocal,
          name: 'my_skill',
          description: 'Imported skill',
          prompt: 'Do the imported work.',
          sortOrder: const Value(0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final updated = await refreshed.future.timeout(
        const Duration(seconds: 2),
      );
      expect(updated.map((skill) => skill.name), contains('my_skill'));
      expect(
        await db.appStateDao.getAllByPrefix('app_initialization.'),
        isEmpty,
        reason: '技能订阅和刷新不应触发应用初始化任务',
      );
    },
  );
}
