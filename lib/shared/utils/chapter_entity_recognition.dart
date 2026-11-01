// 职责: 章节正文中识别小说实体名（角色、地名、技能、物品等）— 最长优先、不重叠匹配，并生成高亮 TextSpan。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/database/novel_content_database.dart

import 'package:flutter/material.dart';

import '../database/novel_content_database.dart';
import '../models/character_profile.dart';

/// 可在正文中被识别的实体条目。
class ChapterEntityMention {
  const ChapterEntityMention({
    required this.entityType,
    required this.id,
    required this.label,
    this.subtitle,
    this.summary,
    this.avatarAssetId,
    this.photoAssetIds = const <String>[],
  });

  final String entityType;
  final String id;
  final String label;
  final String? subtitle;
  final String? summary;
  final String? avatarAssetId;
  final List<String> photoAssetIds;
}

/// 正文中一处实体名匹配。
class ChapterEntityMatch {
  const ChapterEntityMatch({
    required this.start,
    required this.end,
    required this.entity,
  });

  final int start;
  final int end;
  final ChapterEntityMention entity;
}

/// 从各工作区资料构建可识别实体目录；禁用识别时返回空目录。
List<ChapterEntityMention> buildChapterEntityCatalog({
  bool enabled = true,
  required List<CharacterProfile> characters,
  required List<Location> locations,
  required List<Item> skills,
  required List<Item> items,
  required List<Item> creatures,
  required List<Item> factions,
}) {
  if (!enabled) {
    return const <ChapterEntityMention>[];
  }

  final catalog = <ChapterEntityMention>[];

  for (final character in characters) {
    if (character.deletedAt == notDeletedSentinel &&
        character.name.trim().isNotEmpty) {
      catalog.add(characterEntityMention(character));
    }
  }
  for (final location in locations) {
    if (location.deletedAt == notDeletedSentinel &&
        location.name.trim().isNotEmpty) {
      catalog.add(locationEntityMention(location));
    }
  }
  for (final entry in [...skills, ...items, ...creatures, ...factions]) {
    if (entry.deletedAt == notDeletedSentinel &&
        entry.title.trim().isNotEmpty) {
      catalog.add(itemEntityMention(entry));
    }
  }

  catalog.sort((a, b) {
    final byLength = b.label.length.compareTo(a.label.length);
    if (byLength != 0) {
      return byLength;
    }
    return _entityTypePriority(
      a.entityType,
    ).compareTo(_entityTypePriority(b.entityType));
  });

  return catalog;
}

ChapterEntityMention characterEntityMention(CharacterProfile character) =>
    ChapterEntityMention(
      entityType: entityTypeCharacter,
      id: character.id,
      label: character.name.trim(),
      subtitle: character.normalizedRole,
      summary: character.biographyPreview.trim(),
      avatarAssetId: character.avatarAssetId,
      photoAssetIds:
          character.photos?.map((photo) => photo.assetId).toList() ??
          const <String>[],
    );

ChapterEntityMention locationEntityMention(Location location) =>
    ChapterEntityMention(
      entityType: entityTypeLocation,
      id: location.id,
      label: location.name.trim(),
      subtitle: location.type,
      summary: _textPreview(location.description),
      photoAssetIds:
          location.photos?.map((photo) => photo.assetId).toList() ??
          const <String>[],
    );

/// 图鉴条目按自身 type 作为实体类型。
ChapterEntityMention itemEntityMention(Item item) => ChapterEntityMention(
  entityType: item.type,
  id: item.id,
  label: item.title.trim(),
  summary: _textPreview(item.content),
  photoAssetIds:
      item.photos?.map((photo) => photo.assetId).toList() ?? const <String>[],
);

int _entityTypePriority(String entityType) {
  return switch (entityType) {
    entityTypeCharacter => 0,
    entityTypeLocation => 1,
    entityTypeSkill => 2,
    entityTypeItem => 3,
    entityTypeCreature => 4,
    entityTypeFaction => 5,
    _ => 99,
  };
}

String _textPreview(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 200) {
    return trimmed;
  }
  return '${trimmed.substring(0, 200)}...';
}

/// 在 [text] 中按实体目录识别名称（长名优先、区间不重叠）。
List<ChapterEntityMatch> findChapterEntityMatches(
  String text,
  List<ChapterEntityMention> catalog,
) {
  if (text.isEmpty || catalog.isEmpty) {
    return const [];
  }

  final matches = <ChapterEntityMatch>[];
  var index = 0;
  while (index < text.length) {
    ChapterEntityMention? matched;
    for (final entity in catalog) {
      final label = entity.label;
      final end = index + label.length;
      if (end <= text.length && text.substring(index, end) == label) {
        matched = entity;
        break;
      }
    }

    if (matched == null) {
      index++;
      continue;
    }

    matches.add(
      ChapterEntityMatch(
        start: index,
        end: index + matched.label.length,
        entity: matched,
      ),
    );
    index += matched.label.length;
  }

  return matches;
}

/// 将正文拆成普通文本与实体名（斜体）的 [TextSpan] 列表。
List<TextSpan> buildChapterEntityHighlightSpans({
  required String text,
  required List<ChapterEntityMatch> matches,
  required TextStyle baseStyle,
  required TextStyle entityStyle,
}) {
  if (text.isEmpty) {
    return const [];
  }
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start < cursor ||
        match.start < 0 ||
        match.end > text.length ||
        match.start >= match.end ||
        text.substring(match.start, match.end) != match.entity.label) {
      continue;
    }
    if (cursor < match.start) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: entityStyle,
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

/// 根据指针位置判断当前是否悬停在某个实体名上。
ChapterEntityMention? chapterEntityAtTextOffset({
  required int offset,
  required List<ChapterEntityMatch> matches,
}) {
  for (final match in matches) {
    if (offset >= match.start && offset < match.end) {
      return match.entity;
    }
  }
  return null;
}
