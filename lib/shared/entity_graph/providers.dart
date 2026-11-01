// 职责: 实体关系图的 Provider 管理，提供图数据、节点详情等状态。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/entity_graph/graph_widget.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../services/entity_relations_service.dart';
import '../providers/novel_providers.dart';

part 'providers.g.dart';

class EntityGraphNodeDetail {
  const EntityGraphNodeDetail({
    required this.title,
    required this.type,
    this.description,
    this.metaLabel,
    this.metaValue,
  });

  final String title;
  final String type;
  final String? description;
  final String? metaLabel;
  final String? metaValue;
}

@riverpod
EntityRelationsService entityRelationsService(Ref ref, String databasePath) {
  final database = ref.watch(novelContentDatabaseProvider(databasePath));
  return EntityRelationsService(database);
}

@riverpod
Stream<List<RelationSummary>> allRelations(Ref ref, String databasePath) {
  final service = ref.watch(entityRelationsServiceProvider(databasePath));
  return service.watchAllRelations();
}

@riverpod
Future<Map<String, List<RelationSummary>>> characterNetwork(
  Ref ref, {
  required String databasePath,
  required String characterId,
}) async {
  final service = ref.watch(entityRelationsServiceProvider(databasePath));
  return service.getCharacterNetwork(characterId);
}

@riverpod
Future<EntityGraphNodeDetail?> entityGraphNodeDetail(
  Ref ref, {
  required String databasePath,
  required String entityType,
  required String entityId,
}) async {
  final service = ref.watch(novelContentServiceProvider(databasePath));

  switch (entityType) {
    case entityTypeCharacter:
      final character = await service.getCharacterProfileById(entityId);
      if (character == null) {
        return null;
      }
      return EntityGraphNodeDetail(
        title: character.name,
        type: entityTypeCharacter,
        description: _firstNonEmpty([
          character.description,
          character.biography,
        ]),
        metaLabel: 'role',
        metaValue: character.role,
      );
    case entityTypeFaction:
    case entityTypeSkill:
    case entityTypeItem:
    case entityTypeCreature:
      final item = await service.getItemById(entityId);
      if (item == null) {
        return null;
      }
      return EntityGraphNodeDetail(
        title: item.title,
        type: item.type,
        description: _emptyToNull(item.content),
        metaLabel: 'status',
        metaValue: item.status,
      );
    case entityTypeChapter:
      final chapter = await service.getChapterById(entityId);
      if (chapter == null) {
        return null;
      }
      return EntityGraphNodeDetail(
        title: chapter.title ?? '',
        type: entityTypeChapter,
        description: _firstNonEmpty([chapter.outline, chapter.content]),
        metaLabel: 'word_count',
        metaValue: '${chapter.wordCount}',
      );
    case entityTypeForeshadowing:
      final foreshadowing = await service.getForeshadowingById(entityId);
      if (foreshadowing == null) {
        return null;
      }
      return EntityGraphNodeDetail(
        title: foreshadowing.title,
        type: entityTypeForeshadowing,
        description: _firstNonEmpty([
          foreshadowing.setup,
          foreshadowing.payoff,
        ]),
        metaLabel: 'status',
        metaValue: foreshadowing.status,
      );
    default:
      return null;
  }
}

String? _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final compacted = _emptyToNull(value);
    if (compacted != null) {
      return compacted;
    }
  }
  return null;
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
