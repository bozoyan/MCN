// 职责: AgentSkill 版本历史写入编排回归测试 — 验证写入单点、懒回填、turn 聚合、
//   启停不产生版本，以及删除后的孤儿回收。
// 关联文件:
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/database/daos/novel_agent_skill_revision_dao.dart
//   lib/shared/models/agent_skill_revision.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/models/agent_skill_revision.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/providers/agent_skill_providers.dart';
import 'package:reveric/shared/providers/novel_agent_skill_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late InstalledAgentSkillsNotifier notifier;

  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        agentSkillAppDatabaseProvider.overrideWithValue(db),
      ],
    );
    await container.read(installedAgentSkillsProvider.future);
    notifier = container.read(installedAgentSkillsProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<AgentSkillRevisionSummary>> revisions(String skillId) {
    return db.novelAgentSkillRevisionDao.listRevisions(skillId);
  }

  Future<NovelAgentSkillModel> createSkill({String prompt = 'v1'}) {
    return notifier.createNovelLocalSkill(
      InstallSkillInput(
        sourceKind: AgentSkillSourceKind.novelLocal,
        name: '技能一',
        description: 'desc',
        prompt: prompt,
      ),
    );
  }

  group('写入单点', () {
    test('创建技能时写入 install 基线版本', () async {
      final skill = await createSkill();
      final list = await revisions(skill.id);
      expect(list, hasLength(1));
      expect(list.single.changeSource, SkillRevisionSource.install);
      expect(list.single.revision, 1);
    });

    test('编辑内容产生新版本', () async {
      final skill = await createSkill();
      await notifier.updateSnapshotFields(skill.copyWith(prompt: 'v2'));

      final list = await revisions(skill.id);
      expect(list.map((item) => item.revision), [2, 1]);
      expect(list.first.changeSource, SkillRevisionSource.user_edit);
    });

    test('toggleEnabled 不产生版本', () async {
      final skill = await createSkill();
      await notifier.toggleEnabled(skill.id);
      await notifier.toggleEnabled(skill.id);

      expect(await revisions(skill.id), hasLength(1));
      expect(
        container.read(installedAgentSkillsProvider).value!.single.enabled,
        isTrue,
      );
    });

    test('setExecutionBlockedReason 不产生版本', () async {
      final skill = await createSkill();
      await notifier.setExecutionBlockedReason(skill.id, 'takedown');

      expect(await revisions(skill.id), hasLength(1));
    });

    test('内容未变的重复保存不产生版本', () async {
      final skill = await createSkill();
      await notifier.updateSnapshotFields(skill);
      await notifier.updateSnapshotFields(skill);

      expect(await revisions(skill.id), hasLength(1));
    });

    test('rename 产生版本并记录新名称', () async {
      final skill = await createSkill();
      await notifier.rename(skill.id, '技能二');

      final list = await revisions(skill.id);
      expect(list, hasLength(2));
      expect(list.first.name, '技能二');
    });

    test('替换 references 产生版本', () async {
      final skill = await createSkill();
      await notifier.replaceReferencesByName(
        name: skill.name,
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: 'body'),
        ],
      );

      final list = await revisions(skill.id);
      expect(list, hasLength(2));
      expect(list.first.fileCount, 1);
    });
  });

  group('懒回填', () {
    test('v29 前已存在的技能首次编辑时补一条 baseline', () async {
      // 直接写库模拟存量数据：没有任何历史版本。
      await db.novelAgentSkillDao.upsertWithReferences(
        skill: NovelAgentSkillsCompanion(
          id: const Value('nas_legacy'),
          sourceKind: const Value('novel_local'),
          name: const Value('存量技能'),
          description: const Value('desc'),
          prompt: const Value('改之前的指令'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
        references: const [],
      );
      container.invalidate(installedAgentSkillsProvider);
      final loaded = await container.read(installedAgentSkillsProvider.future);
      final legacy = loaded.firstWhere((item) => item.id == 'nas_legacy');
      expect(await revisions('nas_legacy'), isEmpty);

      await notifier.updateSnapshotFields(legacy.copyWith(prompt: '改之后的指令'));

      final list = await revisions('nas_legacy');
      expect(list.map((item) => item.changeSource), [
        SkillRevisionSource.user_edit,
        SkillRevisionSource.baseline,
      ]);
      final baseline = await db.novelAgentSkillRevisionDao.getRevision(
        list.last.id,
      );
      expect(baseline!.prompt, '改之前的指令');
    });

    test('已有历史的技能不会重复补 baseline', () async {
      final skill = await createSkill();
      await notifier.updateSnapshotFields(skill.copyWith(prompt: 'v2'));
      await notifier.updateSnapshotFields(skill.copyWith(prompt: 'v3'));

      final list = await revisions(skill.id);
      expect(
        list.where((item) => item.changeSource == SkillRevisionSource.baseline),
        isEmpty,
      );
    });
  });

  group('turn 聚合', () {
    test('同一 turn 内多次 AI 写入只留一条', () async {
      final skill = await createSkill();
      for (final prompt in ['a', 'b', 'c']) {
        await notifier.updateSnapshotFields(
          skill.copyWith(prompt: prompt),
          changeSource: SkillRevisionSource.ai_edit,
          turnId: 'turn_1',
        );
      }

      final list = await revisions(skill.id);
      expect(list, hasLength(2)); // install 基线 + 本轮一条
      expect(list.first.changeSource, SkillRevisionSource.ai_edit);
      final detail = await db.novelAgentSkillRevisionDao.getRevision(
        list.first.id,
      );
      expect(detail!.prompt, 'c');
    });

    test('不同 turn 各自成条', () async {
      final skill = await createSkill();
      await notifier.updateSnapshotFields(
        skill.copyWith(prompt: 'a'),
        changeSource: SkillRevisionSource.ai_edit,
        turnId: 'turn_1',
      );
      await notifier.updateSnapshotFields(
        skill.copyWith(prompt: 'b'),
        changeSource: SkillRevisionSource.ai_edit,
        turnId: 'turn_2',
      );

      expect(await revisions(skill.id), hasLength(3));
    });

    test('用户手动保存不会并入 AI 的同轮版本', () async {
      final skill = await createSkill();
      await notifier.updateSnapshotFields(
        skill.copyWith(prompt: 'ai'),
        changeSource: SkillRevisionSource.ai_edit,
        turnId: 'turn_1',
      );
      await notifier.updateSnapshotFields(skill.copyWith(prompt: 'user'));

      final list = await revisions(skill.id);
      expect(list.map((item) => item.changeSource), [
        SkillRevisionSource.user_edit,
        SkillRevisionSource.ai_edit,
        SkillRevisionSource.install,
      ]);
    });
  });

  group('删除', () {
    test('remove 后历史与 blob 一并清理', () async {
      final skill = await createSkill();
      await notifier.replaceReferencesByName(
        name: skill.name,
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: 'body'),
        ],
      );

      await notifier.remove(skill.id);

      expect(await revisions(skill.id), isEmpty);
      final blobs = await db
          .customSelect('SELECT COUNT(*) AS c FROM novel_agent_skill_blobs')
          .getSingle();
      expect(blobs.read<int>('c'), 0);
    });
  });
}
