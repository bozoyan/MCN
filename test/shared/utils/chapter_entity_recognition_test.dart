import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/utils/chapter_entity_recognition.dart';

CharacterProfile _character(String id, String name) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return CharacterProfile(
    id: id,
    name: name,
    role: characterRoleSupporting,
    gender: characterGenderUnknown,
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
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Location _location(String id, String name) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Location(
    id: id,
    name: name,
    description: '',
    type: locationTypeGeneric,
    tags: '',
    status: locationStatusActive,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Item _item(String id, String title, {required String type}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Item(
    id: id,
    type: type,
    title: title,
    content: '',
    status: itemEntryStatusActive,
    category: '',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

void main() {
  group('buildChapterEntityCatalog', () {
    test('returns no entities when recognition is disabled', () {
      final catalog = buildChapterEntityCatalog(
        enabled: false,
        characters: [_character('1', '张三')],
        locations: [_location('loc', '青云山')],
        skills: const [],
        items: const [],
        creatures: const [],
        factions: const [],
      );

      expect(catalog, isEmpty);
    });
  });

  group('findChapterEntityMatches', () {
    test('prefers longer labels and avoids overlapping matches', () {
      final catalog = buildChapterEntityCatalog(
        characters: [_character('1', '张'), _character('2', '张三')],
        locations: const [],
        skills: const [],
        items: const [],
        creatures: const [],
        factions: const [],
      );

      final matches = findChapterEntityMatches('张三说话', catalog);

      expect(matches, hasLength(1));
      expect(matches.single.entity.id, '2');
    });

    test('matches locations, skills, items, and creatures', () {
      final catalog = buildChapterEntityCatalog(
        characters: const [],
        locations: [_location('loc', '青云山')],
        skills: [_item('sk', '御剑术', type: entityTypeSkill)],
        items: [_item('it', '青锋剑', type: entityTypeItem)],
        creatures: [_item('cr', '赤焰兽', type: entityTypeCreature)],
        factions: const [],
      );

      final matches = findChapterEntityMatches('在青云山施展御剑术，挥动青锋剑击退赤焰兽', catalog);

      expect(matches, hasLength(4));
      expect(matches.map((m) => m.entity.entityType).toList(), [
        entityTypeLocation,
        entityTypeSkill,
        entityTypeItem,
        entityTypeCreature,
      ]);
    });
  });

  group('buildChapterEntityHighlightSpans', () {
    test('ignores stale matches outside the current text range', () {
      const entity = ChapterEntityMention(
        entityType: entityTypeCharacter,
        id: 'character',
        label: '张三',
      );
      const staleMatches = [
        ChapterEntityMatch(start: 2, end: 4, entity: entity),
      ];

      final spans = buildChapterEntityHighlightSpans(
        text: '张',
        matches: staleMatches,
        baseStyle: const TextStyle(),
        entityStyle: const TextStyle(fontStyle: FontStyle.italic),
      );

      expect(spans, hasLength(1));
      expect(spans.single.text, '张');
    });
  });
}
