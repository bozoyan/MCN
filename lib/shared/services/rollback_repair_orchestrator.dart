// 职责: 在回滚事务内修正历史字段，并覆盖同名对象、迁移其子项与业务引用。
// 关联文件:
//   lib/shared/services/working_overlay.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/content_status.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/data-deletion.md
//   .agents/rules/error-handling.md

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/content_status.dart';
import '../models/outline.dart'
    show outlineStatuses, outlineStatusPending, decodeTimelineJson;

final _log = AppLogger.forModule('RollbackRepair');

class RollbackRepairOrchestrator {
  Future<String> prepare({
    required NovelContentDatabase database,
    required String resourceType,
    required String id,
    required String field,
    required String value,
  }) async {
    try {
      return await database.transaction(() async {
        final repaired = await _normalize(
          database,
          resourceType,
          id,
          field,
          value,
        );
        final table = switch (resourceType) {
          'locations' => 'locations',
          'outlines' => 'outlines',
          'lore' || 'worldbuilding' || 'materials' => 'documents',
          'foreshadowing' => 'foreshadowings',
          'skills' || 'items' || 'factions' || 'creatures' => 'items',
          _ => null,
        };
        if (table != null &&
            (field == 'title' ||
                (table == 'locations' &&
                    (field == 'name' || field == 'parent_id')))) {
          final key = table == 'outlines' ? 'document_id' : 'id';
          final rows = await database
              .customSelect(
                'SELECT * FROM $table WHERE $key = ? AND deleted_at = 0',
                variables: [Variable.withString(id)],
              )
              .get();
          if (rows.isNotEmpty) {
            final row = rows.single;
            final nameColumn = table == 'locations' ? 'name' : 'title';
            final name = field == 'parent_id'
                ? row.read<String>(nameColumn)
                : repaired;
            final parent = field == 'parent_id'
                ? (repaired.isEmpty ? null : repaired)
                : (table == 'documents' || table == 'locations')
                ? row.readNullable<String>('parent_id')
                : null;
            await _overwriteNames(
              database,
              table: table,
              survivor: id,
              name: name,
              parent: parent,
              type: table == 'documents' || table == 'items'
                  ? row.read<String>('type')
                  : null,
            );
          }
        }
        return repaired;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] rollback repair resource=$resourceType id=$id field=$field failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<String> _normalize(
    NovelContentDatabase db,
    String type,
    String id,
    String field,
    String value,
  ) async {
    String enumValue(List<String> allowed, String fallback) =>
        allowed.contains(value) ? value : fallback;
    if (type == 'characters') {
      if (field == 'role') {
        return enumValue(characterRoles, characterRoleSupporting);
      }
      if (field == 'gender') {
        return enumValue(characterGenders, characterGenderUnknown);
      }
      if (field == 'first_appear_chapter_id' && value.isNotEmpty) {
        final chapter = await db.chapterDao.getById(value);
        if (chapter == null || !chapter.isChapter) {
          return '';
        }
      }
    }
    if (type == 'locations') {
      if (field == 'type') {
        return enumValue(locationTypes, locationTypeGeneric);
      }
      if (field == 'status') {
        return enumValue(locationStatuses, locationStatusActive);
      }
      if (field == 'parent_id' && value.isNotEmpty) {
        final seen = <String>{id};
        String? cursor = value;
        while (cursor != null) {
          if (!seen.add(cursor)) {
            return '';
          }
          final row = await db.locationDao.getById(cursor);
          if (row == null) {
            return '';
          }
          cursor = row.parentId;
        }
      }
    }
    if (type == 'outlines') {
      if (field == 'beats') {
        return jsonEncode(
          decodeTimelineJson(value)
              .map(
                (beat) => beat
                    .copyWith(
                      status: outlineStatuses.contains(beat.status)
                          ? beat.status
                          : outlineStatusPending,
                      chapterCount: beat.chapterCount < 1
                          ? 1
                          : beat.chapterCount,
                    )
                    .toJson(),
              )
              .toList(),
        );
      }
      if (field == 'status') {
        return enumValue(outlineStatuses, outlineStatusPending);
      }
      if (field == 'start_chapter_num') {
        return '${(int.tryParse(value) ?? 1).clamp(1, 2147483647)}';
      }
    }
    if (type == 'foreshadowing') {
      if (field == 'status') {
        return enumValue(foreshadowingStatuses, foreshadowingStatusPlanted);
      }
      if (field.endsWith('_chapter_id') || field.endsWith('_scene_id')) {
        if (value.isEmpty) {
          return value;
        }
        final screenplay = await db.screenplayDao.getRoot();
        if (field.endsWith('_chapter_id')) {
          final chapter = await db.chapterDao.getById(value);
          if (screenplay != null ||
              chapter == null ||
              chapter.type == nodeTypeVolume) {
            return '';
          }
        } else {
          final scene = await db.screenplayDao.getScene(value);
          if (screenplay == null ||
              scene == null ||
              scene.screenplayId != screenplay.id) {
            return '';
          }
        }
      }
    }
    if (const {'skills', 'items', 'factions', 'creatures'}.contains(type) &&
        field == 'status') {
      return enumValue(itemEntryStatuses, itemEntryStatusActive);
    }
    if (type == 'screenplay_scenes') {
      if (field == 'interior_exterior') {
        final interior = jsonDecode(value) as String?;
        return jsonEncode(
          const {'interior', 'exterior', 'interior_exterior'}.contains(interior)
              ? interior
              : null,
        );
      }
      if (field == 'emotion') {
        final tags = jsonDecode(value) as List?;
        return jsonEncode(
          tags
              ?.whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(),
        );
      }
    }
    if (const {
          'lore',
          'worldbuilding',
          'materials',
          'outlines',
          'skills',
          'items',
          'factions',
          'creatures',
        }.contains(type) &&
        field == 'title') {
      return value.replaceAll('/', '／').replaceAll('?', '？');
    }
    return value;
  }

  Future<void> _overwriteNames(
    NovelContentDatabase db, {
    required String table,
    required String survivor,
    required String name,
    String? parent,
    String? type,
  }) async {
    if (name.trim().isEmpty) {
      return;
    }
    final key = table == 'outlines' ? 'document_id' : 'id';
    final nameColumn = table == 'locations' ? 'name' : 'title';
    final vars = <Variable>[
      Variable.withString(survivor),
      Variable.withString(name),
    ];
    var where = '$key != ? AND $nameColumn = ? AND deleted_at = 0';
    if (table == 'locations') {
      where = '$key != ? AND trim($nameColumn) = trim(?) AND deleted_at = 0';
    }
    if (table == 'documents' || table == 'locations') {
      where += parent == null ? ' AND parent_id IS NULL' : ' AND parent_id = ?';
      if (parent != null) {
        vars.add(Variable.withString(parent));
      }
    }
    if (type != null) {
      where += ' AND type = ?';
      vars.add(Variable.withString(type));
    }
    final collisions = await db
        .customSelect(
          'SELECT * FROM $table WHERE $where ORDER BY $key',
          variables: vars,
        )
        .get();
    for (final row in collisions) {
      await _merge(
        db,
        table: table,
        loser: row.read<String>(key),
        survivor: survivor,
        type: type,
      );
    }
  }

  Future<void> _merge(
    NovelContentDatabase db, {
    required String table,
    required String loser,
    required String survivor,
    String? type,
  }) async {
    final key = table == 'outlines' ? 'document_id' : 'id';
    // 秒级软删除唯一键可能已经有同名墓碑；为每个覆盖对象保留独立时间值。
    final occupied = await db
        .customSelect('SELECT MAX(deleted_at) AS stamp FROM $table')
        .getSingle();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final previous = occupied.readNullable<int>('stamp') ?? 0;
    final stamp = previous >= now ? previous + 1 : now;
    await db.customUpdate(
      'UPDATE $table SET deleted_at = ?, updated_at = ? WHERE $key = ?',
      variables: [
        Variable.withInt(stamp),
        Variable.withInt(now),
        Variable.withString(loser),
      ],
      updates: _tables(db, table),
    );
    _log.info('[DB] SOFT_DELETE $table id=$loser overwritten_by=$survivor');
    await (db.update(db.workingChanges)..where(
          (row) => row.resourceId.equals(loser) & row.status.equals('active'),
        ))
        .write(
          WorkingChangesCompanion(
            status: const Value('rejected'),
            updatedAt: Value(DateTime.now()),
          ),
        );

    if (table == 'documents' || table == 'locations') {
      String? destination = survivor;
      if (table == 'documents') {
        final receiver = await db.documentDao.getById(survivor);
        if (receiver != null && !receiver.isFolder) {
          destination = receiver.parentId;
        }
      }
      final children = await db
          .customSelect(
            'SELECT * FROM $table WHERE parent_id = ? AND deleted_at = 0',
            variables: [Variable.withString(loser)],
          )
          .get();
      for (final child in children) {
        final childId = child.read<String>('id');
        final childName = child.read<String>(
          table == 'locations' ? 'name' : 'title',
        );
        if (childId == survivor) {
          continue;
        }
        // 保留接收侧已存在的同名子项，将被覆盖侧的引用和后代合并进去。
        final existing = await db
            .customSelect(
              'SELECT id FROM $table WHERE ${destination == null ? 'parent_id IS NULL' : 'parent_id = ?'} AND ${table == 'locations' ? 'trim(name)' : 'title'} = ${table == 'locations' ? 'trim(?)' : '?'} AND deleted_at = 0${table == 'documents' ? ' AND type = ?' : ''}',
              variables: [
                if (destination != null) Variable.withString(destination),
                Variable.withString(childName),
                if (table == 'documents')
                  Variable.withString(child.read<String>('type')),
              ],
            )
            .get();
        if (existing.isNotEmpty) {
          await _merge(
            db,
            table: table,
            loser: childId,
            survivor: existing.first.read<String>('id'),
            type: table == 'documents' ? child.read<String>('type') : null,
          );
        } else {
          await db.customUpdate(
            'UPDATE $table SET parent_id = ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable<String>(destination),
              Variable.withInt(now),
              Variable.withString(childId),
            ],
            updates: _tables(db, table),
          );
        }
      }
    }
    if (table == 'locations') {
      await (db.update(
        db.screenplaySceneElements,
      )..where((r) => r.locationId.equals(loser))).write(
        ScreenplaySceneElementsCompanion(
          locationId: Value(survivor),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await (db.update(
        db.novelMaps,
      )..where((r) => r.locationId.equals(loser))).write(
        NovelMapsCompanion(
          locationId: Value(survivor),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final pins =
          await (db.select(db.mapLocations)..where(
                (r) =>
                    r.locationId.equals(loser) &
                    r.deletedAt.equals(notDeletedSentinel),
              ))
              .get();
      for (final pin in pins) {
        final duplicates =
            await (db.select(db.mapLocations)..where(
                  (r) =>
                      r.mapId.equals(pin.mapId) &
                      r.locationId.equals(survivor) &
                      r.deletedAt.equals(notDeletedSentinel),
                ))
                .get();
        await (db.update(
          db.mapLocations,
        )..where((r) => r.id.equals(pin.id))).write(
          duplicates.isEmpty
              ? MapLocationsCompanion(
                  locationId: Value(survivor),
                  updatedAt: Value(DateTime.now()),
                )
              : MapLocationsCompanion(
                  deletedAt: Value(
                    DateTime.fromMillisecondsSinceEpoch(stamp * 1000),
                  ),
                  updatedAt: Value(DateTime.now()),
                ),
        );
      }
    }
    if (table == 'outlines') {
      final count = await db
          .customSelect(
            'SELECT COALESCE(MAX(sort_order), -1) AS last_order FROM outline_beats WHERE outline_document_id = ?',
            variables: [Variable.withString(survivor)],
          )
          .getSingle();
      final beats = await db.outlineDao.getBeatRows(loser);
      var order = count.read<int>('last_order') + 1;
      for (final beat in beats) {
        await (db.update(
          db.outlineBeats,
        )..where((r) => r.id.equals(beat.id))).write(
          OutlineBeatsCompanion(
            outlineDocumentId: Value(survivor),
            sortOrder: Value(order++),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
    final entityType = switch (table) {
      'locations' => entityTypeLocation,
      'foreshadowings' => entityTypeForeshadowing,
      'items' => type,
      _ => null,
    };
    if (entityType != null) {
      await (db.update(db.entityRelations)..where(
            (r) => r.sourceType.equals(entityType) & r.sourceId.equals(loser),
          ))
          .write(
            EntityRelationsCompanion(
              sourceId: Value(survivor),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await (db.update(db.entityRelations)..where(
            (r) => r.targetType.equals(entityType) & r.targetId.equals(loser),
          ))
          .write(
            EntityRelationsCompanion(
              targetId: Value(survivor),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  Set<TableInfo> _tables(NovelContentDatabase db, String table) =>
      switch (table) {
        'documents' => {db.documents},
        'locations' => {db.locations},
        'outlines' => {db.outlines},
        'foreshadowings' => {db.foreshadowings},
        'items' => {db.items},
        _ => throw ArgumentError.value(table),
      };
}
