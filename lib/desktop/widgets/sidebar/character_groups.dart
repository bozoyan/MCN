// 职责: 把人物列表按分组摊平成侧边栏行（分组行 + 人物行），无分组人物不聚合、直接平铺。
// 关联文件:
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/models/character_profile.dart

import '../../../shared/models/character_profile.dart';

/// 侧边栏人物面板的一行：分组标题行或人物行。
sealed class CharacterSidebarRow {
  const CharacterSidebarRow();
}

/// 分组标题行：可折叠，右侧显示该分组下的人物数。
class CharacterGroupRow extends CharacterSidebarRow {
  const CharacterGroupRow({
    required this.name,
    required this.count,
    required this.isExpanded,
  });

  final String name;
  final int count;
  final bool isExpanded;
}

/// 人物行。[groupName] 为空表示该人物没有任何分组，直接平铺在分组区之后。
class CharacterEntryRow extends CharacterSidebarRow {
  const CharacterEntryRow({required this.character, this.groupName});

  final CharacterProfile character;
  final String? groupName;

  /// 组内人物缩进一级，未分组人物与分组行同级。
  int get depth => groupName == null ? 0 : 1;
}

/// 按分组摊平人物列表。
///
/// 规则：
/// - 只有 tags 非空的人物参与聚合；没有分组的人物保持原顺序平铺在所有分组之后。
/// - 一个人物属于多个分组时，在每个分组下各出现一次。
/// - 分组按人数降序排列，人数相同按名称升序；组内保持传入顺序。
/// - [matches] 返回 false 的人物整体不参与（分组人数也随之减少），空分组不出现。
/// - [isSearching] 为 true 时忽略 [expandedGroups] 全部展开，避免命中项藏在折叠分组里；
///   搜索态的展开不写回 [expandedGroups]，清空搜索后仍是用户手动的折叠状态。
List<CharacterSidebarRow> buildCharacterSidebarRows({
  required List<CharacterProfile> characters,
  required Set<String> expandedGroups,
  required bool Function(CharacterProfile character) matches,
  bool isSearching = false,
}) {
  final grouped = <String, List<CharacterProfile>>{};
  final ungrouped = <CharacterProfile>[];

  for (final character in characters) {
    if (!matches(character)) {
      continue;
    }
    final groups = <String>{};
    for (final tag in character.tags) {
      final name = tag.trim();
      if (name.isNotEmpty) {
        groups.add(name);
      }
    }
    if (groups.isEmpty) {
      ungrouped.add(character);
      continue;
    }
    for (final group in groups) {
      grouped.putIfAbsent(group, () => []).add(character);
    }
  }

  final groupNames = grouped.keys.toList()
    ..sort((a, b) {
      final byCount = grouped[b]!.length.compareTo(grouped[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  final rows = <CharacterSidebarRow>[];
  for (final name in groupNames) {
    final members = grouped[name]!;
    final isExpanded = isSearching || expandedGroups.contains(name);
    rows.add(
      CharacterGroupRow(
        name: name,
        count: members.length,
        isExpanded: isExpanded,
      ),
    );
    if (!isExpanded) {
      continue;
    }
    for (final character in members) {
      rows.add(CharacterEntryRow(character: character, groupName: name));
    }
  }

  for (final character in ungrouped) {
    rows.add(CharacterEntryRow(character: character));
  }

  return rows;
}
