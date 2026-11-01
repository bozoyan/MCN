// 职责: 地图相关 Provider — 提供地点、地图与地图地点坐标的状态管理。
// 关联文件:
//   lib/shared/services/maps_service.dart
//   lib/shared/database/novel_content_database.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../services/maps_service.dart';
import 'novel_providers.dart';

part 'maps_providers.g.dart';

@riverpod
LocationsService locationsService(Ref ref, String databasePath) {
  final database = ref.watch(novelContentDatabaseProvider(databasePath));
  return LocationsService(database);
}

@riverpod
MapsService mapsService(Ref ref, String databasePath) {
  final database = ref.watch(novelContentDatabaseProvider(databasePath));
  return MapsService(database);
}

@riverpod
MapLocationsService mapLocationsService(Ref ref, String databasePath) {
  final database = ref.watch(novelContentDatabaseProvider(databasePath));
  return MapLocationsService(database);
}

@riverpod
Stream<List<Location>> locations(Ref ref, String databasePath) {
  final service = ref.watch(locationsServiceProvider(databasePath));
  return service.watchLocations();
}

@riverpod
Location? locationById(
  Ref ref, {
  required String databasePath,
  required String locationId,
}) {
  final locationsAsync = ref.watch(locationsProvider(databasePath));
  return locationsAsync.when(
    data: (list) => list.where((l) => l.id == locationId).firstOrNull,
    loading: () => null,
    error: (error, stackTrace) => null,
  );
}

@riverpod
Stream<List<NovelMap>> maps(Ref ref, String databasePath) {
  final service = ref.watch(mapsServiceProvider(databasePath));
  return service.watchMaps();
}

@riverpod
NovelMap? mapById(
  Ref ref, {
  required String databasePath,
  required String mapId,
}) {
  final mapsAsync = ref.watch(mapsProvider(databasePath));
  return mapsAsync.when(
    data: (list) => list.where((m) => m.id == mapId).firstOrNull,
    loading: () => null,
    error: (error, stackTrace) => null,
  );
}

@riverpod
Stream<List<MapLocation>> mapLocations(
  Ref ref, {
  required String databasePath,
  required String mapId,
}) {
  final service = ref.watch(mapLocationsServiceProvider(databasePath));
  return service.watchMapLocations(mapId);
}
