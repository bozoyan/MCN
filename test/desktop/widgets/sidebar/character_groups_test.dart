// 职责: 验证侧边栏人物分组摊平规则 — 无分组不聚合、多分组重复出现、按人数排序、搜索强制展开。
// 关联文件:
//   lib/desktop/widgets/sidebar/character_groups.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/sidebar/character_groups.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/character_profile.dart';

void main() {
  test('没有分组的人物不聚合，直接平铺在分组之后', () {
    final rows = buildCharacterSidebarRows(
      characters: [
        _character(id: 'a', name: '陈屿', tags: const ['云岚宗']),
        _character(id: 'b', name: '陈峰'),
        _character(id: 'c', name: '李想'),
      ],
      expandedGroups: const {},
      matches: (_) => true,
    );

    expect(_describe(rows), ['组 云岚宗 (1)', '陈峰', '李想']);
  });

  test('全员无分组时一行分组行都不出现', () {
    final rows = buildCharacterSidebarRows(
      characters: [
        _character(id: 'a', name: '陈屿'),
        _character(id: 'b', name: '陈峰', tags: const ['  ']),
      ],
      expandedGroups: const {},
      matches: (_) => true,
    );

    expect(rows.whereType<CharacterGroupRow>(), isEmpty);
    expect(_describe(rows), ['陈屿', '陈峰']);
  });

  test('分组按人数降序、同人数按名称升序，展开后组内人物缩进一级', () {
    final rows = buildCharacterSidebarRows(
      characters: [
        _character(id: 'a', name: '陈屿', tags: const ['纳兰家']),
        _character(id: 'b', name: '苏瑶', tags: const ['云岚宗']),
        _character(id: 'c', name: '张伟', tags: const ['云岚宗']),
        _character(id: 'd', name: '王芳', tags: const ['反派']),
      ],
      expandedGroups: const {'云岚宗', '反派'},
      matches: (_) => true,
    );

    expect(_describe(rows), [
      '组 云岚宗 (2)',
      '  苏瑶',
      '  张伟',
      '组 反派 (1)',
      '  王芳',
      '组 纳兰家 (1)',
    ]);
  });

  test('多分组人物在每个分组下各出现一次，且不再进入平铺区', () {
    final rows = buildCharacterSidebarRows(
      characters: [
        _character(id: 'a', name: '陈屿', tags: const ['云岚宗', '内门弟子']),
        _character(id: 'b', name: '张伟', tags: const ['云岚宗']),
      ],
      expandedGroups: const {'云岚宗', '内门弟子'},
      matches: (_) => true,
    );

    expect(_describe(rows), [
      '组 云岚宗 (2)',
      '  陈屿',
      '  张伟',
      '组 内门弟子 (1)',
      '  陈屿',
    ]);
    expect(
      rows.whereType<CharacterEntryRow>().where((row) => row.depth == 0),
      isEmpty,
    );
  });

  test('搜索时忽略折叠状态全部展开，且空分组不出现', () {
    final rows = buildCharacterSidebarRows(
      characters: [
        _character(id: 'a', name: '陈屿', tags: const ['云岚宗']),
        _character(id: 'b', name: '苏瑶', tags: const ['纳兰家']),
        _character(id: 'c', name: '陈峰'),
      ],
      expandedGroups: const {},
      matches: (character) => character.name.contains('陈'),
      isSearching: true,
    );

    expect(_describe(rows), ['组 云岚宗 (1)', '  陈屿', '陈峰']);
  });
}

List<String> _describe(List<CharacterSidebarRow> rows) {
  return rows.map((row) {
    return switch (row) {
      CharacterGroupRow() => '组 ${row.name} (${row.count})',
      CharacterEntryRow() => '${'  ' * row.depth}${row.character.name}',
    };
  }).toList();
}

CharacterProfile _character({
  required String id,
  required String name,
  List<String> tags = const [],
}) {
  return CharacterProfile(
    id: id,
    name: name,
    role: 'supporting',
    gender: 'unknown',
    aliases: const [],
    tags: tags,
    biography: '',
    appearance: '',
    description: '',
    currentState: '',
    identity: '',
    age: '',
    motivation: '',
    arc: '',
    personality: '',
    behaviorTags: const [],
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: notDeletedSentinel,
  );
}
