// 职责: 验证地图导航推导的纯函数 — 制图草案目标所属的顶层 world（子地图草案的投递校验），
//       以及选中地点时画布切到最近一张有图的祖先。
// 关联文件:
//   lib/shared/models/map_studio_nav.dart
//   lib/shared/services/ai/chat_turn_runner.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/map_studio_nav.dart';

void main() {
  final world = _location('world', type: locationTypeWorld);
  final city = _location('city', type: locationTypeCity, parentId: 'world');
  final street = _location(
    'street',
    type: locationTypeLandmark,
    parentId: 'city',
  );
  final orphanContinent = _location('continent', type: locationTypeContinent);
  final orphanTown = _location(
    'town',
    type: locationTypeCity,
    parentId: 'continent',
  );
  final dangling = _location(
    'dangling',
    type: locationTypeCity,
    parentId: 'missing',
  );
  final byId = {
    for (final location in [
      world,
      city,
      street,
      orphanContinent,
      orphanTown,
      dangling,
    ])
      location.id: location,
  };

  group('mapTopLevelWorldOf', () {
    test('a top-level world is its own root', () {
      expect(mapTopLevelWorldOf('world', byId)?.id, 'world');
    });

    test('sub-locations at any depth resolve to their world', () {
      expect(mapTopLevelWorldOf('city', byId)?.id, 'world');
      expect(mapTopLevelWorldOf('street', byId)?.id, 'world');
    });

    test('rejects unknown ids, broken parent chains and non-world roots', () {
      expect(mapTopLevelWorldOf('nope', byId), isNull);
      expect(mapTopLevelWorldOf('dangling', byId), isNull);
      expect(mapTopLevelWorldOf('continent', byId), isNull);
      expect(mapTopLevelWorldOf('town', byId), isNull);
    });
  });

  test('selecting a location shows the nearest mapped ancestor', () {
    final nav = MapStudioNav.resolve(
      world: world,
      maps: [_map('map_world', 'world'), _map('map_city', 'city')],
      locations: byId.values.toList(),
      requestedOwnerId: 'world',
    );
    expect(nav.owner.id, 'world');
    expect(nav.mappedLocationIds, {'world', 'city'});
    expect(nav.ownerForSelection('street'), 'city');
    expect(nav.ownerForSelection('city'), 'world');
  });
}

Location _location(String id, {required String type, String? parentId}) {
  final now = DateTime(2026);
  return Location(
    id: id,
    name: id,
    description: '',
    type: type,
    parentId: parentId,
    tags: '',
    status: locationStatusActive,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

NovelMap _map(String id, String locationId) {
  final now = DateTime(2026);
  return NovelMap(
    id: id,
    name: id,
    description: '',
    type: mapTypeWorld,
    locationId: locationId,
    width: 1280,
    height: 720,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}
