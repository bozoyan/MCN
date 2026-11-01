// 职责: 地图相关服务 — 地点、地图与地图地点坐标的 CRUD 操作。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/models/screenplay.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart';

import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/screenplay.dart';
import '../utils/random_id.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';
import '../utils/unique_display_name.dart';
import 'entity_relations_service.dart';
import 'production/subject_references.dart';

final _log = AppLogger.forModule('MapsService');

/// 同一父级下的其他地点已经占用了这个名称。
class DuplicateLocationNameException implements Exception {
  const DuplicateLocationNameException(this.name);
  final String name;

  @override
  String toString() => 'Location name already exists: $name';
}

class LocationsService {
  LocationsService(
    this._database, {
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
  }) : _buildEntityId = idBuilder;

  final NovelContentDatabase _database;
  final ShortEntityIdBuilder _buildEntityId;
  late final EntityRelationsService _entityRelationsService =
      EntityRelationsService(_database, idBuilder: _buildEntityId);

  Future<bool> _idExists(String id) async {
    final row =
        await (_database.selectOnly(_database.locations)
              ..addColumns([_database.locations.id])
              ..where(_database.locations.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Stream<List<Location>> watchLocations() => _database.locationDao.watchAll();

  Future<List<Location>> getLocations() => _database.locationDao.getAll();

  Future<Location?> getLocationById(String id) =>
      _database.locationDao.getById(id);

  Future<List<Location>> getLocationsByType(String type) =>
      (_database.select(_database.locations)
            ..where((table) => table.type.equals(type))
            ..where((table) => table.deletedAt.equals(notDeletedSentinel))
            ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
          .get();

  Future<List<Location>> getChildLocations(String parentId) =>
      (_database.select(_database.locations)
            ..where((table) => table.parentId.equals(parentId))
            ..where((table) => table.deletedAt.equals(notDeletedSentinel))
            ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
          .get();

  Future<List<String>> getAncestorIds(String locationId) async {
    final result = <String>[];
    final visited = <String>{};
    String? currentId = locationId;
    while (currentId != null && visited.add(currentId)) {
      final location = await getLocationById(currentId);
      if (location == null) {
        break;
      }
      currentId = location.parentId;
      if (currentId != null) {
        result.add(currentId);
      }
    }
    return result;
  }

  Future<List<String>> getDescendantIds(String locationId) async {
    final result = <String>[];
    final pending = <String>[locationId];
    while (pending.isNotEmpty) {
      final current = pending.removeAt(0);
      final children = await getChildLocations(current);
      for (final child in children) {
        result.add(child.id);
        pending.add(child.id);
      }
    }
    return result;
  }

  Future<List<Location>> getFullPath(String locationId) async {
    final ids = (await getAncestorIds(locationId)).reversed.toList()
      ..add(locationId);
    final result = <Location>[];
    for (final id in ids) {
      final location = await getLocationById(id);
      if (location != null) {
        result.add(location);
      }
    }
    return result;
  }

  // 与 Dart String.trim 的 Unicode 空白范围一致，历史名称无需批量重写。
  static const _nameWhitespace =
      '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0'
      '\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007'
      '\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff';

  Future<void> _assertNameAvailable(
    String name, {
    required String? parentId,
    String? exceptId,
  }) async {
    final duplicate = await _database
        .customSelect(
          'SELECT id FROM locations WHERE deleted_at = 0 AND trim(name, ?) = ? '
          '${parentId == null ? 'AND parent_id IS NULL ' : 'AND parent_id = ? '}'
          '${exceptId == null ? '' : 'AND id != ? '}LIMIT 1',
          variables: [
            Variable.withString(_nameWhitespace),
            Variable.withString(name.trim()),
            if (parentId != null) Variable.withString(parentId),
            if (exceptId != null) Variable.withString(exceptId),
          ],
          readsFrom: {_database.locations},
        )
        .getSingleOrNull();
    if (duplicate != null) {
      throw DuplicateLocationNameException(name.trim());
    }
  }

  /// 仅供没有用户输入名称的快速新建入口使用；显式名称继续由 createLocation 拒绝同名。
  Future<String> createLocationWithDefaultName({
    required String defaultName,
    String type = locationTypeGeneric,
    String? parentId,
  }) => _database.transaction(() async {
    final locations = _database.locations;
    final names =
        await (_database.selectOnly(locations)
              ..addColumns([locations.name])
              ..where(
                parentId == null
                    ? locations.parentId.isNull()
                    : locations.parentId.equals(parentId),
              ))
            .get();
    final name = buildUniqueDisplayName(
      baseName: defaultName,
      existingNames: names.map((row) => row.read(_database.locations.name)!),
    );
    return createLocation(name: name, type: type, parentId: parentId);
  });

  Future<String> createLocation({
    required String name,
    String description = '',
    String type = locationTypeGeneric,
    String? parentId,
    List<String> tags = const [],
    Map<String, dynamic>? meta,
  }) async {
    try {
      return await _database.transaction(() async {
        if (parentId != null && await getLocationById(parentId) == null) {
          throw ArgumentError('Parent location not found: $parentId');
        }
        await _assertNameAvailable(name, parentId: parentId);
        final now = DateTime.now();
        final row = await _database
            .customSelect(
              'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM locations',
            )
            .getSingle();
        return insertWithShortEntityId(
          type: ShortEntityIdType.location,
          tableName: 'locations',
          idExists: _idExists,
          buildId: _buildEntityId,
          insert: (id) => _database
              .into(_database.locations)
              .insert(
                LocationsCompanion.insert(
                  id: id,
                  name: name,
                  description: Value(description),
                  type: Value(type),
                  parentId: Value(parentId),
                  tags: Value(tags.join(',')),
                  meta: Value(meta),
                  sortOrder: Value(row.read<int>('max_order') + 1),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              ),
        );
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=INSERT failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 追加已导入图片库的照片；已在列表中的资产跳过。
  Future<List<SubjectPhoto>> addPhotos({
    required String id,
    required List<String> assetIds,
  }) async {
    try {
      return await _database.transaction(() async {
        final entry = await _database.locationDao.getById(id);
        if (entry == null) {
          throw StateError('Location no longer exists');
        }
        final next = [...?entry.photos];
        final existing = next.map((photo) => photo.assetId).toSet();
        for (final assetId in assetIds) {
          if (existing.add(assetId)) {
            next.add(SubjectPhoto(assetId: assetId));
          }
        }
        await updateLocation(id: id, photos: next);
        return next;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=ADD_PHOTOS id=$id count=${assetIds.length}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 只从地点照片列表移除，不删除图片文件。
  Future<List<SubjectPhoto>> removePhoto({
    required String id,
    required String assetId,
  }) async {
    try {
      return await _database.transaction(() async {
        final entry = await _database.locationDao.getById(id);
        final next = [
          for (final photo in entry?.photos ?? const <SubjectPhoto>[])
            if (photo.assetId != assetId) photo,
        ];
        await updateLocation(id: id, photos: next);
        return next;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=REMOVE_PHOTO id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<SubjectPhoto>> renamePhoto({
    required String id,
    required String assetId,
    required String name,
  }) async {
    try {
      return await _database.transaction(() async {
        final entry = await _database.locationDao.getById(id);
        final photos = entry?.photos ?? const <SubjectPhoto>[];
        bool matches(SubjectPhoto photo) => photo.assetId == assetId;
        if (!photos.any(matches)) {
          throw StateError('Photo no longer exists');
        }
        final next = photos
            .map(
              (photo) =>
                  matches(photo) ? photo.copyWith(name: name.trim()) : photo,
            )
            .toList();
        await updateLocation(id: id, photos: next);
        return next;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=RENAME_PHOTO id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> updateLocation({
    required String id,
    String? name,
    String? description,
    String? type,
    String? parentId,
    bool clearParentId = false,
    List<String>? tags,
    String? status,
    Map<String, dynamic>? meta,
    bool clearMeta = false,
    List<SubjectPhoto>? photos,
  }) async {
    try {
      await _database.transaction(() async {
        if (name != null || parentId != null || clearParentId) {
          final existing = await getLocationById(id);
          final nextName = name ?? existing?.name;
          final nextParentId = parentId != null || clearParentId
              ? parentId
              : existing?.parentId;
          // 名称和父级都没变时允许保存存量记录，不清洗历史同名数据。
          if (nextName != null &&
              (existing == null ||
                  existing.name.trim() != nextName.trim() ||
                  existing.parentId != nextParentId)) {
            await _assertNameAvailable(
              nextName,
              parentId: nextParentId,
              exceptId: id,
            );
          }
        }
        if (parentId != null && parentId.isNotEmpty) {
          if (parentId == id || (await getAncestorIds(parentId)).contains(id)) {
            throw ArgumentError(
              'Cannot set parent to $parentId — it would create a circular reference',
            );
          }
          if (await getLocationById(parentId) == null) {
            throw ArgumentError('Parent location not found: $parentId');
          }
        }
        await (_database.update(
          _database.locations,
        )..where((table) => table.id.equals(id))).write(
          LocationsCompanion(
            photos: photos == null ? const Value.absent() : Value(photos),
            name: name != null ? Value(name) : const Value.absent(),
            description: description != null
                ? Value(description)
                : const Value.absent(),
            type: type != null ? Value(type) : const Value.absent(),
            parentId: parentId != null || clearParentId
                ? Value(parentId)
                : const Value.absent(),
            tags: tags != null ? Value(tags.join(',')) : const Value.absent(),
            status: status != null ? Value(status) : const Value.absent(),
            meta: meta != null || clearMeta
                ? Value(meta)
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=UPDATE id=$id failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<ScreenplaySceneReference>> getScreenplaySceneReferences(
    String id,
  ) => _database.screenplayDao.getLocationSceneReferences(id);

  Future<void> deleteLocation(
    String id, {
    bool cascadeOrphans = true,
    bool restoreHistory = false,
  }) async {
    try {
      await _database.transaction(() async {
        await requireUnusedProductionSubject(_database, locationId: id);
        if (!restoreHistory) {
          final references = await getScreenplaySceneReferences(id);
          if (references.isNotEmpty) {
            throw ScreenplayServiceException(
              'entity_in_use',
              'Location is still referenced by screenplay scenes.',
              details: references.map((scene) => scene.sceneId).toList(),
            );
          }
        }
        if (cascadeOrphans) {
          final children = await getChildLocations(id);
          for (final child in children) {
            await (_database.update(
              _database.locations,
            )..where((table) => table.id.equals(child.id))).write(
              LocationsCompanion(
                parentId: const Value(null),
                updatedAt: Value(DateTime.now()),
              ),
            );
          }
        }
        await (_database.delete(
          _database.mapLocations,
        )..where((table) => table.locationId.equals(id))).go();
        await _entityRelationsService.deleteRelationsForEntity(
          entityType: entityTypeLocation,
          entityId: id,
        );
        await (_database.delete(
          _database.locations,
        )..where((table) => table.id.equals(id))).go();
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=locations operation=DELETE id=$id failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> reorderLocations(List<String> ids) async {
    await _database.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (_database.update(_database.locations)
              ..where((table) => table.id.equals(ids[i])))
            .write(LocationsCompanion(sortOrder: Value(i)));
      }
    });
  }
}

class MapsService {
  MapsService(this._database);

  final NovelContentDatabase _database;

  Stream<List<NovelMap>> watchMaps() => (_database.select(
    _database.novelMaps,
  )..orderBy([(table) => OrderingTerm(expression: table.sortOrder)])).watch();

  Future<List<NovelMap>> getMaps() => (_database.select(
    _database.novelMaps,
  )..orderBy([(table) => OrderingTerm(expression: table.sortOrder)])).get();

  Future<NovelMap?> getMapById(String id) => (_database.select(
    _database.novelMaps,
  )..where((table) => table.id.equals(id))).getSingleOrNull();

  Future<NovelMap?> getMapByLocationId(String locationId) =>
      (_database.select(_database.novelMaps)
            ..where((table) => table.locationId.equals(locationId))
            ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)])
            ..limit(1))
          .getSingleOrNull();

  Future<String> getOrCreateMapForLocation({
    required String locationId,
    required String name,
    required String type,
  }) => _database.transaction(() async {
    final existing = await getMapByLocationId(locationId);
    return existing?.id ??
        createMap(name: name, type: type, locationId: locationId);
  });

  Future<String> createMap({
    required String name,
    String type = mapTypeWorld,
    String? description,
    String? locationId,
    double width = 1000.0,
    double height = 800.0,
    Map<String, dynamic>? settings,
    bool ensureUniqueName = false,
  }) async {
    final maps = await getMaps();
    final now = DateTime.now();
    final id = buildRandomId('map');
    await _database
        .into(_database.novelMaps)
        .insert(
          NovelMapsCompanion.insert(
            id: id,
            name: ensureUniqueName
                ? buildUniqueDisplayName(
                    baseName: name,
                    existingNames: maps.map((map) => map.name),
                  )
                : name,
            description: Value(description ?? ''),
            type: Value(type),
            locationId: Value(locationId),
            width: Value(width),
            height: Value(height),
            settings: Value(settings),
            sortOrder: Value(maps.length),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateMap({
    required String id,
    String? name,
    String? description,
    String? type,
    String? locationId,
    bool clearLocationId = false,
    double? width,
    double? height,
    Map<String, dynamic>? settings,
  }) =>
      (_database.update(
        _database.novelMaps,
      )..where((table) => table.id.equals(id))).write(
        NovelMapsCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          description: description != null
              ? Value(description)
              : const Value.absent(),
          type: type != null ? Value(type) : const Value.absent(),
          locationId: locationId != null || clearLocationId
              ? Value(locationId)
              : const Value.absent(),
          width: width != null ? Value(width) : const Value.absent(),
          height: height != null ? Value(height) : const Value.absent(),
          settings: settings != null ? Value(settings) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
}

class MapLocationsService {
  MapLocationsService(this._database);
  final NovelContentDatabase _database;

  Stream<List<MapLocation>> watchMapLocations(String mapId) =>
      (_database.select(_database.mapLocations)
            ..where((table) => table.mapId.equals(mapId))
            ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
          .watch();

  Future<List<MapLocation>> getMapLocations(String mapId) =>
      (_database.select(_database.mapLocations)
            ..where((table) => table.mapId.equals(mapId))
            ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
          .get();

  Future<String> addLocationToMap({
    required String mapId,
    required String locationId,
    double x = 0.0,
    double y = 0.0,
    double? width,
    double? height,
    Map<String, dynamic>? style,
  }) async {
    final now = DateTime.now();
    final id = buildRandomId('map_location');
    await _database
        .into(_database.mapLocations)
        .insert(
          MapLocationsCompanion.insert(
            id: id,
            mapId: mapId,
            locationId: locationId,
            x: Value(x),
            y: Value(y),
            width: Value(width),
            height: Value(height),
            style: Value(style),
            sortOrder: Value((await getMapLocations(mapId)).length),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateMapLocation({
    required String id,
    double? x,
    double? y,
    double? width,
    double? height,
    Map<String, dynamic>? style,
  }) =>
      (_database.update(
        _database.mapLocations,
      )..where((table) => table.id.equals(id))).write(
        MapLocationsCompanion(
          x: x != null ? Value(x) : const Value.absent(),
          y: y != null ? Value(y) : const Value.absent(),
          width: width != null ? Value(width) : const Value.absent(),
          height: height != null ? Value(height) : const Value.absent(),
          style: style != null ? Value(style) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
