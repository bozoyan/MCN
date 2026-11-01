// 职责: 测试 NovelAgentSkillRevisionDao — 版本追加、turn 聚合、内容寻址去重、
//   裁剪与孤儿 blob 回收。
// 关联文件:
//   lib/shared/database/daos/novel_agent_skill_revision_dao.dart
//   lib/shared/models/agent_skill_revision.dart
//   lib/shared/models/novel_agent_skill.dart

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/agent_skill_reference.dart';
import 'package:reveric/shared/models/agent_skill_revision.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    await db.novelAgentSkillDao.upsert(
      NovelAgentSkillsCompanion(
        id: const Value('nas_1'),
        sourceKind: const Value('novel_local'),
        name: const Value('技能一'),
        description: const Value('desc'),
        prompt: const Value('prompt v1'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  NovelAgentSkillModel skill({
    String id = 'nas_1',
    String name = '技能一',
    String prompt = 'prompt v1',
    String description = 'desc',
    List<AgentSkillReferenceFile> references = const [],
  }) {
    return NovelAgentSkillModel(
      id: id,
      sourceKind: AgentSkillSourceKind.novelLocal,
      name: name,
      description: description,
      prompt: prompt,
      references: references,
    );
  }

  Future<int> blobCount() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM novel_agent_skill_blobs')
        .getSingle();
    return rows.read<int>('c');
  }

  group('appendRevision', () {
    test('第一条版本号为 1，并可读回全量快照', () async {
      final revision = await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(
          references: const [
            AgentSkillReferenceFile(path: 'references/a.md', content: 'file a'),
          ],
        ),
        changeSource: SkillRevisionSource.baseline,
      );
      expect(revision, 1);

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      expect(list, hasLength(1));
      expect(list.single.changeSource, SkillRevisionSource.baseline);
      expect(list.single.fileCount, 1);

      final detail = await db.novelAgentSkillRevisionDao.getRevision(
        list.single.id,
      );
      expect(detail!.prompt, 'prompt v1');
      expect(detail.references.single.content, 'file a');
    });

    test('无 turn_id 时每次都新增一条', () async {
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(prompt: 'v1'),
        changeSource: SkillRevisionSource.user_edit,
      );
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(prompt: 'v2'),
        changeSource: SkillRevisionSource.user_edit,
      );

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      expect(list.map((item) => item.revision), [2, 1]);
    });

    test('同一 turn_id 内多次写入只保留一条，且内容为最后一次', () async {
      for (final content in ['a', 'b', 'c']) {
        await db.novelAgentSkillRevisionDao.appendRevision(
          content: skill(
            prompt: 'prompt $content',
            references: [
              AgentSkillReferenceFile(
                path: 'references/$content.md',
                content: content,
              ),
            ],
          ),
          changeSource: SkillRevisionSource.ai_edit,
          turnId: 'turn_1',
        );
      }

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      expect(list, hasLength(1));
      expect(list.single.revision, 1);

      final detail = await db.novelAgentSkillRevisionDao.getRevision(
        list.single.id,
      );
      expect(detail!.prompt, 'prompt c');
      expect(detail.references.single.path, 'references/c.md');
    });

    test('不同 turn_id 各自成条', () async {
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(prompt: 'v1'),
        changeSource: SkillRevisionSource.ai_edit,
        turnId: 'turn_1',
      );
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(prompt: 'v2'),
        changeSource: SkillRevisionSource.ai_edit,
        turnId: 'turn_2',
      );

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      expect(list, hasLength(2));
    });
  });

  group('内容寻址', () {
    test('只改 prompt 的多次编辑不新增 blob', () async {
      const reference = AgentSkillReferenceFile(
        path: 'references/shared.md',
        content: '附件正文保持不变',
      );
      for (var i = 0; i < 10; i++) {
        await db.novelAgentSkillRevisionDao.appendRevision(
          content: skill(prompt: 'prompt $i', references: const [reference]),
          changeSource: SkillRevisionSource.user_edit,
        );
      }

      expect(
        await db.novelAgentSkillRevisionDao.listRevisions('nas_1'),
        hasLength(10),
      );
      expect(await blobCount(), 1);
    });

    test('被删除的附件仍可从历史读回正文', () async {
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(
          references: const [
            AgentSkillReferenceFile(
              path: 'references/gone.md',
              content: '将被删除的正文',
            ),
          ],
        ),
        changeSource: SkillRevisionSource.user_edit,
      );
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(prompt: 'prompt v2'),
        changeSource: SkillRevisionSource.user_edit,
      );

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      final oldest = list.last;
      final detail = await db.novelAgentSkillRevisionDao.getRevision(oldest.id);
      expect(detail!.references.single.content, '将被删除的正文');
    });
  });

  group('裁剪与回收', () {
    test('超出上限后删除最旧版本，孤儿 blob 被 GC', () async {
      for (var i = 0; i < 4; i++) {
        await db.novelAgentSkillRevisionDao.appendRevision(
          content: skill(
            prompt: 'prompt $i',
            references: [
              AgentSkillReferenceFile(
                path: 'references/$i.md',
                content: 'body $i',
              ),
            ],
          ),
          changeSource: SkillRevisionSource.user_edit,
        );
      }
      expect(await blobCount(), 4);

      final removed = await db.novelAgentSkillRevisionDao.pruneRevisions(
        'nas_1',
        keep: 2,
      );
      expect(removed, 2);

      final gcd = await db.novelAgentSkillRevisionDao.gcBlobs();
      expect(gcd, 2);
      expect(await blobCount(), 2);

      final list = await db.novelAgentSkillRevisionDao.listRevisions('nas_1');
      expect(list.map((item) => item.revision), [4, 3]);
    });

    test('未超出上限时不删除', () async {
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(),
        changeSource: SkillRevisionSource.user_edit,
      );
      expect(
        await db.novelAgentSkillRevisionDao.pruneRevisions('nas_1', keep: 50),
        0,
      );
    });

    test('hardDelete 技能后附件行不残留', () async {
      await db.novelAgentSkillDao.upsertWithReferences(
        skill: const NovelAgentSkillsCompanion(
          id: Value('nas_1'),
          sourceKind: Value('novel_local'),
          name: Value('技能一'),
          description: Value('desc'),
          prompt: Value('prompt v1'),
        ),
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: 'body'),
        ],
      );
      expect(
        await db.novelAgentSkillDao.getReferencesBySkillIds(['nas_1']),
        isNotEmpty,
      );

      await db.novelAgentSkillDao.hardDelete('nas_1');

      // 本库未开启 PRAGMA foreign_keys，级联不会执行，必须由 DAO 显式清理。
      expect(
        await db.novelAgentSkillDao.getReferencesBySkillIds(['nas_1']),
        isEmpty,
      );
    });

    test('hardDelete 技能后历史一并消失，blob 由 GC 回收', () async {
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: skill(
          references: const [
            AgentSkillReferenceFile(path: 'references/a.md', content: 'body'),
          ],
        ),
        changeSource: SkillRevisionSource.user_edit,
      );
      await db.novelAgentSkillDao.hardDelete('nas_1');

      expect(
        await db.novelAgentSkillRevisionDao.listRevisions('nas_1'),
        isEmpty,
      );
      await db.novelAgentSkillRevisionDao.gcBlobs();
      expect(await blobCount(), 0);
    });
  });

  group('写入判重辅助', () {
    test('hasAnyRevision / latestContentHash 反映最新一条', () async {
      expect(
        await db.novelAgentSkillRevisionDao.hasAnyRevision('nas_1'),
        false,
      );
      expect(
        await db.novelAgentSkillRevisionDao.latestContentHash('nas_1'),
        isNull,
      );

      final content = skill(prompt: 'v1');
      await db.novelAgentSkillRevisionDao.appendRevision(
        content: content,
        changeSource: SkillRevisionSource.install,
      );

      expect(await db.novelAgentSkillRevisionDao.hasAnyRevision('nas_1'), true);
      expect(
        await db.novelAgentSkillRevisionDao.latestContentHash('nas_1'),
        content.contentHash,
      );
    });

    test('enabled / sortOrder 变化不改变内容指纹', () async {
      final base = skill();
      expect(
        base.copyWith(enabled: false, sortOrder: 9).contentHash,
        base.contentHash,
      );
    });

    test('附件正文变化会改变内容指纹', () async {
      final before = skill(
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: 'a'),
        ],
      );
      final after = skill(
        references: const [
          AgentSkillReferenceFile(path: 'references/a.md', content: 'b'),
        ],
      );
      expect(before.contentHash, isNot(after.contentHash));
    });
  });
}
