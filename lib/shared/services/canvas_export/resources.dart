// 职责: 按资源类型批量采集导出白名单正文与有限父级链身份，不展开未引用容器。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/canvas_export/orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/db-query-aggregation.md
//   .agents/rules/json.md

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../database/novel_content_database.dart';
import '../../models/canvas_export.dart';

String canvasResourceKey(String type, String id) => '$type:$id';
typedef _Ref = ({String type, String id});

class CanvasResourceCollection {
  const CanvasResourceCollection(this.resources, this.issues);
  final Map<String, CanvasExportObject> resources;
  final List<CanvasExportObject> issues;
}

class _Record {
  const _Record(this.value, {this.dependencies = const [], this.parent});
  final CanvasExportObject value;
  final List<_Ref> dependencies;
  final _Ref? parent;
}

Future<CanvasResourceCollection> collectCanvasResources(
  NovelContentDatabase db,
  List<CanvasNode> nodes,
) async {
  final direct = <_Ref>{
    for (final node in nodes)
      if (node.type == canvasNodeTypeReference &&
          canvasExportResourceTypes.contains(node.refType) &&
          node.refId != null)
        (type: node.refType!, id: node.refId!),
  };
  final resources = <String, CanvasExportObject>{};
  final parents = <String, String>{};
  final issues = <CanvasExportObject>[];
  var pending = direct;
  var content = true;
  while (pending.isNotEmpty) {
    final next = <_Ref>{};
    final grouped = groupBy(pending, (ref) => ref.type);
    for (final type in grouped.keys.sorted()) {
      for (final batch in grouped[type]!.slices(400)) {
        final records = await _read(
          db,
          type,
          batch.map((r) => r.id).toSet(),
          content,
        );
        for (final ref in batch) {
          final key = canvasResourceKey(ref.type, ref.id);
          final record = records[ref.id];
          resources[key] =
              record?.value ?? _value(type, ref.id, ref.id, false, null);
          if (record?.parent case final parent?) {
            parents[key] = canvasResourceKey(parent.type, parent.id);
            next.add(parent);
          }
          if (content &&
              record != null &&
              record.value['status'] == 'available') {
            next.addAll(record.dependencies);
          }
          if (!content && resources[key]!['status'] == 'missing') {
            issues.add(
              canvasExportIssue(
                'warning',
                'missing_dependency',
                'An indirect resource is missing.',
                resourceType: type,
                resourceId: ref.id,
              ),
            );
          }
        }
      }
    }
    content = false;
    pending = next
        .where(
          (ref) => !resources.containsKey(canvasResourceKey(ref.type, ref.id)),
        )
        .toSet();
  }
  final checked = <String>{};
  for (final key in parents.keys.sorted()) {
    final path = <String>{};
    String? cursor = key;
    while (cursor != null && !checked.contains(cursor)) {
      if (!path.add(cursor)) {
        final resource = resources[cursor]!;
        issues.add(
          canvasExportIssue(
            'info',
            'cycle',
            'A resource parent chain contains a cycle.',
            resourceType: resource['type'] as String,
            resourceId: resource['id'] as String,
          ),
        );
        break;
      }
      cursor = parents[cursor];
    }
    checked.addAll(path);
  }
  return CanvasResourceCollection(resources, issues);
}

CanvasExportObject _value(
  String type,
  String id,
  String title,
  bool available,
  CanvasExportObject? payload,
) => {
  'type': type,
  'id': id,
  'title': title,
  'status': available ? 'available' : 'missing',
  'detail_level': available && payload != null ? 'content' : 'identity',
  'payload': available ? payload : null,
};

_Ref? _parent(String type, String? id) =>
    id == null ? null : (type: type, id: id);

Future<Map<String, _Record>> _identities(
  NovelContentDatabase db,
  String type,
  Set<String> ids,
  TableInfo table,
  GeneratedColumn<String> id,
  GeneratedColumn<String> title,
  GeneratedColumn<DateTime> deletedAt, {
  GeneratedColumn<String>? parent,
  Expression<bool>? filter,
}) async {
  final query = db.selectOnly(table)
    ..addColumns([id, title, deletedAt, ?parent])
    ..where(id.isIn(ids));
  if (filter != null) {
    query.where(filter);
  }
  final rows = await query.get();
  return {
    for (final row in rows)
      row.read(id)!: _Record(
        _value(
          type,
          row.read(id)!,
          row.read(title) ?? '',
          row.read(deletedAt) == notDeletedSentinel,
          null,
        ),
        parent: parent == null ? null : _parent(type, row.read(parent)),
      ),
  };
}

Future<Map<String, _Record>> _read(
  NovelContentDatabase db,
  String type,
  Set<String> ids,
  bool content,
) async {
  switch (type) {
    case entityTypeChapter:
      final t = db.chapters;
      if (!content) {
        return _identities(
          db,
          type,
          ids,
          t,
          t.id,
          t.title,
          t.deletedAt,
          parent: t.parentId,
        );
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.title ?? '',
              row.deletedAt == notDeletedSentinel,
              {
                'node_kind': row.type,
                'parent_id': row.parentId,
                'sibling_order': row.siblingOrder,
                'content': row.content,
                'outline': row.outline,
                'brief': row.brief,
                'status': row.stat,
                'word_count': row.wordCount,
              },
            ),
            parent: _parent(type, row.parentId),
          ),
      };
    case canvasNodeRefTypeOutline:
      final t = db.outlines;
      if (!content) {
        return _identities(
          db,
          type,
          ids,
          t,
          t.documentId,
          t.title,
          t.deletedAt,
        );
      }
      final beats =
          await (db.select(db.outlineBeats)
                ..where(
                  (t) =>
                      t.outlineDocumentId.isIn(ids) &
                      t.deletedAt.equals(notDeletedSentinel),
                )
                ..orderBy([
                  (t) => OrderingTerm(expression: t.sortOrder),
                  (t) => OrderingTerm(expression: t.id),
                ]))
              .get();
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.documentId.isIn(ids))).get())
          row.documentId: _Record(
            _value(
              type,
              row.documentId,
              row.title,
              row.deletedAt == notDeletedSentinel,
              {
                'content': row.content,
                'status': row.status,
                'start_chapter_num': row.startChapterNum,
                'beats': [
                  for (final beat in beats.where(
                    (b) => b.outlineDocumentId == row.documentId,
                  ))
                    {
                      'id': beat.id,
                      'title': beat.title,
                      'content': beat.content,
                      'status': beat.status,
                      'chapter_count': beat.chapterCount,
                      'sort_order': beat.sortOrder,
                    },
                ],
              },
            ),
          ),
      };
    case entityTypeCharacter:
      final t = db.characterProfiles;
      if (!content) {
        return _identities(db, type, ids, t, t.id, t.name, t.deletedAt);
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.name,
              row.deletedAt == notDeletedSentinel,
              {
                'role': row.role,
                'gender': row.gender,
                'aliases': row.aliases,
                'tags': row.tags,
                'biography': row.biography,
                'appearance': row.appearance,
                'description': row.description,
                'current_state': row.currentState,
                'identity': row.identity,
                'age': row.age,
                'motivation': row.motivation,
                'arc': row.arc,
                'personality': row.personality,
                'behavior_tags': [
                  for (final tag in row.behaviorTags)
                    {'tag': tag.tag, 'context': tag.context},
                ],
                'first_appear_chapter_id': row.firstAppearChapterId,
              },
            ),
            dependencies: [
              ?_parent(entityTypeChapter, row.firstAppearChapterId),
            ],
          ),
      };
    case entityTypeForeshadowing:
      final t = db.foreshadowings;
      if (!content) {
        return _identities(db, type, ids, t, t.id, t.title, t.deletedAt);
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.title,
              row.deletedAt == notDeletedSentinel,
              {
                'setup': row.setup,
                'payoff': row.payoff,
                'status': row.status,
                'setup_chapter_id': row.setupChapterId,
                'payoff_chapter_id': row.payoffChapterId,
                'setup_scene_id': row.setupSceneId,
                'payoff_scene_id': row.payoffSceneId,
              },
            ),
            dependencies: [
              ?_parent(entityTypeChapter, row.setupChapterId),
              ?_parent(entityTypeChapter, row.payoffChapterId),
              ?_parent(canvasNodeRefTypeScreenplayScene, row.setupSceneId),
              ?_parent(canvasNodeRefTypeScreenplayScene, row.payoffSceneId),
            ],
          ),
      };
    case entityTypeLocation:
      final t = db.locations;
      if (!content) {
        return _identities(
          db,
          type,
          ids,
          t,
          t.id,
          t.name,
          t.deletedAt,
          parent: t.parentId,
        );
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.name,
              row.deletedAt == notDeletedSentinel,
              {
                'description': row.description,
                'location_type': row.type,
                'tags': row.tags,
                'status': row.status,
                'parent_id': row.parentId,
              },
            ),
            parent: _parent(type, row.parentId),
          ),
      };
    case canvasNodeRefTypeDocument:
      final t = db.documents;
      if (!content) {
        return _identities(
          db,
          type,
          ids,
          t,
          t.id,
          t.title,
          t.deletedAt,
          parent: t.parentId,
        );
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.title,
              row.deletedAt == notDeletedSentinel,
              {
                'document_type': row.type,
                'content': row.content,
                'category': row.category,
                'tags': row.tags,
                'status': row.status,
                'parent_id': row.parentId,
                'is_folder': row.isFolder,
              },
            ),
            parent: _parent(type, row.parentId),
          ),
      };
    case entityTypeItem ||
        entityTypeFaction ||
        entityTypeSkill ||
        entityTypeCreature:
      final t = db.items;
      if (!content) {
        return _identities(
          db,
          type,
          ids,
          t,
          t.id,
          t.title,
          t.deletedAt,
          filter: t.type.equals(type),
        );
      }
      return {
        for (final row in await (db.select(
          t,
        )..where((t) => t.id.isIn(ids) & t.type.equals(type))).get())
          row.id: _Record(
            _value(
              type,
              row.id,
              row.title,
              row.deletedAt == notDeletedSentinel,
              {
                'content': row.content,
                'category': row.category,
                'status': row.status,
              },
            ),
          ),
      };
    case canvasNodeRefTypeScreenplayScene:
      return _scenes(db, ids, content);
    default:
      throw StateError('Unsupported canvas resource type.');
  }
}

Future<Map<String, _Record>> _scenes(
  NovelContentDatabase db,
  Set<String> ids,
  bool content,
) async {
  if (!content) {
    final rows = await db
        .customSelect(
          "SELECT s.id, s.title, (s.deleted_at = 0 AND e.deleted_at = 0 AND se.deleted_at = 0 AND r.deleted_at = 0 AND e.screenplay_id = s.screenplay_id AND se.screenplay_id = s.screenplay_id AND EXISTS (SELECT 1 FROM screenplay_scene_elements h WHERE h.scene_id = s.id AND h.episode_id = s.episode_id AND h.type = 'scene_heading' AND h.deleted_at = 0)) AS available FROM screenplay_scenes s LEFT JOIN screenplay_episodes e ON e.id = s.episode_id LEFT JOIN screenplay_seasons se ON se.id = e.season_id LEFT JOIN screenplays r ON r.id = s.screenplay_id WHERE s.id IN (${ids.map((_) => '?').join(',')})",
          variables: [for (final id in ids) Variable.withString(id)],
          readsFrom: {
            db.screenplayScenes,
            db.screenplayEpisodes,
            db.screenplaySeasons,
            db.screenplays,
            db.screenplaySceneElements,
          },
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): _Record(
          _value(
            canvasNodeRefTypeScreenplayScene,
            row.read<String>('id'),
            row.read<String>('title'),
            row.readNullable<int>('available') == 1,
            null,
          ),
        ),
    };
  }
  final scenes = await (db.select(
    db.screenplayScenes,
  )..where((t) => t.id.isIn(ids))).get();
  final episodes = {
    for (final row in await (db.select(
      db.screenplayEpisodes,
    )..where((t) => t.id.isIn(scenes.map((s) => s.episodeId)))).get())
      row.id: row,
  };
  final seasons = {
    for (final row in await (db.select(
      db.screenplaySeasons,
    )..where((t) => t.id.isIn(episodes.values.map((e) => e.seasonId)))).get())
      row.id: row,
  };
  final roots = {
    for (final row
        in await (db.select(db.screenplays)..where(
              (t) =>
                  t.id.isIn(scenes.map((s) => s.screenplayId)) &
                  t.deletedAt.equals(notDeletedSentinel),
            ))
            .get())
      row.id,
  };
  final elements =
      await (db.select(db.screenplaySceneElements)
            ..where(
              (t) =>
                  t.sceneId.isIn(ids) & t.deletedAt.equals(notDeletedSentinel),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();
  // 场头的所属集与编号由同一次查询读取，供有效性校验和正文导出共用。
  final headings = await db
      .customSelect(
        "SELECT h.scene_id, h.episode_id, (SELECT COUNT(*) FROM screenplay_scene_elements h2 JOIN screenplay_scenes s2 ON s2.id = h2.scene_id AND s2.deleted_at = 0 WHERE h2.episode_id = h.episode_id AND h2.type = 'scene_heading' AND h2.deleted_at = 0 AND h2.sort_order <= h.sort_order) AS scene_number FROM screenplay_scene_elements h WHERE h.type = 'scene_heading' AND h.deleted_at = 0 AND h.scene_id IN (${ids.map((_) => '?').join(',')})",
        variables: [for (final id in ids) Variable.withString(id)],
        readsFrom: {db.screenplaySceneElements, db.screenplayScenes},
      )
      .get();
  final headingsByScene = {
    for (final row in headings) row.read<String>('scene_id'): row,
  };
  return {
    for (final scene in scenes)
      scene.id: (() {
        final episode = episodes[scene.episodeId];
        final season = seasons[episode?.seasonId];
        final available =
            scene.deletedAt == notDeletedSentinel &&
            episode != null &&
            episode.deletedAt == notDeletedSentinel &&
            season != null &&
            season.deletedAt == notDeletedSentinel &&
            episode.screenplayId == scene.screenplayId &&
            season.screenplayId == scene.screenplayId &&
            roots.contains(scene.screenplayId) &&
            headingsByScene[scene.id]?.read<String>('episode_id') ==
                scene.episodeId;
        final body = elements.where((e) => e.sceneId == scene.id).toList();
        return _Record(
          _value(
            canvasNodeRefTypeScreenplayScene,
            scene.id,
            scene.title,
            available,
            available
                ? {
                    'season': {
                      'id': season.id,
                      'number': season.seasonNumber,
                      'title': season.title,
                    },
                    'episode': {
                      'id': episode.id,
                      'number': episode.episodeNumber,
                      'title': episode.title,
                    },
                    'scene_number': headingsByScene[scene.id]!.read<int>(
                      'scene_number',
                    ),
                    'synopsis': scene.synopsis,
                    'stage': scene.stage,
                    'elements': [
                      for (final element in body)
                        {
                          'id': element.id,
                          'type': element.type,
                          'text': element.textContent,
                          'character_id': element.characterId,
                          'extension': element.extension,
                          'location_id': element.locationId,
                          'interior_exterior': element.interiorExterior,
                          'time_label': element.timeLabel,
                        },
                    ],
                  }
                : null,
          ),
          dependencies: [
            for (final element in body) ...[
              ?_parent(entityTypeCharacter, element.characterId),
              ?_parent(entityTypeLocation, element.locationId),
            ],
          ],
        );
      })(),
  };
}
