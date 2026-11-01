// 职责: 实体关系图数据层测试 — 验证深度筛选在未选中时仍生效。
// 关联文件:
//   lib/shared/entity_graph/data.dart
//   lib/shared/database/novel_content_database.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/entity_graph/data.dart';

RelationSummary _relation({
  required String id,
  required String sourceType,
  required String sourceId,
  required String targetType,
  required String targetId,
}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return RelationSummary(
    id: id,
    sourceType: sourceType,
    sourceId: sourceId,
    targetType: targetType,
    targetId: targetId,
    relationType: characterRelationFriend,
    status: 'active',
    proof: '',
    sortOrder: 0,
    createdAt: epoch,
    updatedAt: epoch,
  );
}

CharacterProfile _character({
  required String id,
  required String name,
  required String role,
}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return CharacterProfile(
    id: id,
    name: name,
    role: role,
    gender: '',
    aliases: const [],
    tags: const [],
    biography: '',
    appearance: '',
    description: '',
    identity: '',
    age: '',
    motivation: '',
    arc: '',
    personality: '',
    behaviorTags: const [],
    currentState: '',
    sortOrder: 0,
    createdAt: epoch,
    updatedAt: epoch,
    deletedAt: epoch,
  );
}

void main() {
  test(
    'ended edges cannot expand depth or influence current center candidates',
    () {
      final active = _relation(
        id: 'bc',
        sourceType: 'character',
        sourceId: 'b',
        targetType: 'character',
        targetId: 'c',
      );
      final ended = RelationSummary(
        id: 'ab',
        sourceType: 'character',
        sourceId: 'a',
        targetType: 'character',
        targetId: 'b',
        relationType: 'friend',
        status: 'ended',
        proof: '',
        sortOrder: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(
        filterEntityGraphRelations(
          allRelations: [ended, active],
          selectedEntityKey: 'character_a',
          depth: 2,
        ),
        isEmpty,
      );
      expect(
        filterEntityGraphRelations(
          allRelations: [ended, active],
          depth: 2,
        ).map((r) => r.id),
        ['bc'],
      );
      expect(
        entityGraphCenterCandidateKeys(
          relations: [ended, active],
          nameMap: {'character_a': 'A', 'character_b': 'B', 'character_c': 'C'},
        ),
        ['character_b', 'character_c'],
      );
      expect(
        relationsForEntityKey([ended, active], 'character_a').single.id,
        'ab',
      );
    },
  );

  test(
    'filterRelationsByEntityTypes keeps relations within selected types',
    () {
      final relations = [
        _relation(
          id: '1',
          sourceType: entityTypeCharacter,
          sourceId: 'a',
          targetType: entityTypeCharacter,
          targetId: 'b',
        ),
        _relation(
          id: '2',
          sourceType: entityTypeCharacter,
          sourceId: 'a',
          targetType: entityTypeFaction,
          targetId: 'f1',
        ),
        _relation(
          id: '3',
          sourceType: entityTypeFaction,
          sourceId: 'f1',
          targetType: entityTypeFaction,
          targetId: 'f2',
        ),
      ];

      final characterOnly = filterRelationsByEntityTypes(relations, {
        entityTypeCharacter,
      });
      expect(characterOnly.map((r) => r.id).toList(), ['1']);

      final characterAndFaction = filterRelationsByEntityTypes(relations, {
        entityTypeCharacter,
        entityTypeFaction,
      });
      expect(characterAndFaction.map((r) => r.id).toSet(), {'1', '2', '3'});
    },
  );

  test(
    'filterEntityGraphRelations applies depth from default center when unselected',
    () {
      final relations = [
        _relation(
          id: '1',
          sourceType: entityTypeCharacter,
          sourceId: 'hero',
          targetType: entityTypeCharacter,
          targetId: 'ally',
        ),
        _relation(
          id: '2',
          sourceType: entityTypeCharacter,
          sourceId: 'ally',
          targetType: entityTypeCharacter,
          targetId: 'distant',
        ),
        _relation(
          id: '3',
          sourceType: entityTypeCharacter,
          sourceId: 'distant',
          targetType: entityTypeCharacter,
          targetId: 'far',
        ),
      ];

      final depthOne = filterEntityGraphRelations(
        allRelations: relations,
        selectedEntityKey: null,
        defaultCenterEntityKey: 'character_hero',
        depth: 1,
      );
      expect(depthOne.map((r) => r.id).toSet(), {'1'});

      final depthTwo = filterEntityGraphRelations(
        allRelations: relations,
        selectedEntityKey: null,
        defaultCenterEntityKey: 'character_hero',
        depth: 2,
      );
      expect(depthTwo.map((r) => r.id).toSet(), {'1', '2'});
    },
  );

  test('filterEntityGraphRelations uses explicit center as BFS origin', () {
    final relations = [
      _relation(
        id: '1',
        sourceType: entityTypeCharacter,
        sourceId: 'hero',
        targetType: entityTypeCharacter,
        targetId: 'ally',
      ),
      _relation(
        id: '2',
        sourceType: entityTypeCharacter,
        sourceId: 'ally',
        targetType: entityTypeCharacter,
        targetId: 'distant',
      ),
      _relation(
        id: '3',
        sourceType: entityTypeCharacter,
        sourceId: 'distant',
        targetType: entityTypeCharacter,
        targetId: 'far',
      ),
    ];

    final fromDistant = filterEntityGraphRelations(
      allRelations: relations,
      defaultCenterEntityKey: 'character_distant',
      depth: 1,
    );
    expect(fromDistant.map((r) => r.id).toSet(), {'2', '3'});
  });

  test(
    'entityGraphCenterCandidateKeys lists named entities sorted by name',
    () {
      final relations = [
        _relation(
          id: '1',
          sourceType: entityTypeCharacter,
          sourceId: 'b',
          targetType: entityTypeCharacter,
          targetId: 'a',
        ),
      ];
      final keys = entityGraphCenterCandidateKeys(
        relations: relations,
        nameMap: {'character_b': 'Zhou', 'character_a': 'Meng'},
      );
      expect(keys, ['character_a', 'character_b']);
    },
  );

  test(
    'resolveEffectiveCenterEntityKey keeps override only if still a candidate',
    () {
      expect(
        resolveEffectiveCenterEntityKey(
          overrideKey: 'character_ally',
          defaultKey: 'character_hero',
          candidateKeys: const ['character_hero', 'character_ally'],
        ),
        'character_ally',
      );
      expect(
        resolveEffectiveCenterEntityKey(
          overrideKey: 'character_ally',
          defaultKey: 'character_hero',
          candidateKeys: const ['character_hero'],
        ),
        'character_hero',
      );
    },
  );

  test('resolveDefaultCenterEntityKey prefers protagonist in graph', () {
    final relations = [
      _relation(
        id: '1',
        sourceType: entityTypeCharacter,
        sourceId: 'hero',
        targetType: entityTypeCharacter,
        targetId: 'other',
      ),
    ];
    final characters = [
      _character(id: 'other', name: 'Other', role: characterRoleSupporting),
      _character(id: 'hero', name: 'Hero', role: characterRoleProtagonist),
    ];

    expect(
      resolveDefaultCenterEntityKey(
        characters: characters,
        relations: relations,
      ),
      'character_hero',
    );
  });
}
