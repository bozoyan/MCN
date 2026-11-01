// 职责: 验证系统 Agent 恢复不会误改自定义 Agent，并可按选择覆盖系统默认值。
// 关联文件:
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/initialization/agent_seeds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restores missing defaults and only overwrites them when requested',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.now();
      await database.globalAgentDao.upsert(
        GlobalAgent(
          id: 'system_monologue',
          scope: agentScopeGlobal,
          novelId: '',
          slug: 'monologue_narrator',
          name: 'Customized system agent',
          description: 'customized',
          prompt: 'custom prompt',
          category: 'primary',
          mode: 'chat',
          enabled: false,
          useCustomPrompt: true,
          sortOrder: 0,
          allowedToolNames: const ['Read'],
          ignoredSkillNames: const ['custom-skill'],
          createdAt: now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
      await database.globalAgentDao.upsert(
        GlobalAgent(
          id: 'custom_agent',
          scope: agentScopeGlobal,
          novelId: '',
          slug: 'user-defined',
          name: 'User defined',
          description: 'custom',
          prompt: 'custom',
          category: 'subagent',
          mode: 'chat',
          enabled: true,
          useCustomPrompt: true,
          sortOrder: 1,
          allowedToolNames: const [],
          ignoredSkillNames: const [],
          createdAt: now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );

      await database.customStatement(
        "UPDATE agents SET allowed_tool_names = '[\"Read\"]' WHERE id = 'system_monologue'",
      );
      final restoredMissing = await restoreDefaultGlobalAgents(
        database,
        overwriteExisting: false,
      );
      expect(restoredMissing, greaterThan(0));

      final preserved = await database.globalAgentDao.getBySlug(
        'monologue_narrator',
      );
      expect(preserved?.name, 'Customized system agent');
      expect(preserved?.prompt, 'custom prompt');
      expect(preserved?.useCustomPrompt, isTrue);

      await restoreDefaultGlobalAgents(database, overwriteExisting: true);
      final reset = await database.globalAgentDao.getBySlug(
        'monologue_narrator',
      );
      expect(reset?.id, 'system_monologue');
      expect(reset?.name, '独白叙述者');
      expect(reset?.description, '角色内心独白叙述');
      expect(reset?.mode, 'monologue');
      expect(reset?.enabled, isTrue);
      expect(reset?.useCustomPrompt, isFalse);
      expect(reset?.prompt, isEmpty);
      expect(reset?.allowedToolNames, ['Read']);

      final custom = await database.globalAgentDao.getBySlug('user-defined');
      expect(custom?.name, 'User defined');
      expect(custom?.prompt, 'custom');
    },
  );
}
