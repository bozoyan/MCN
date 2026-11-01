// 职责: 地图工作台数据模型与地名回读解析的单元测试
// 关联文件:
//   lib/shared/models/map_studio_models.dart
//   lib/shared/services/map_place_name_reader.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/map_place_name_reader.dart';
import 'package:reveric/shared/models/map_studio_models.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

void main() {
  group('deriveMapRegionsAndPlaces', () {
    Location loc(String id, String type, {String? parentId}) {
      return Location(
        id: id,
        name: id,
        description: '',
        type: type,
        parentId: parentId,
        tags: '',
        meta: null,
        status: locationStatusActive,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deletedAt: notDeletedSentinel,
      );
    }

    test('疆域单独供 prompt 使用，全部子地点都进入坐标识别候选', () {
      final locations = [
        loc('world', locationTypeWorld),
        loc('north', locationTypeContinent, parentId: 'world'),
        loc('kingdom', locationTypeCountry, parentId: 'north'),
        loc('city', locationTypeCity, parentId: 'kingdom'),
        loc('other', locationTypeCountry),
      ];
      final (regions, places) = deriveMapRegionsAndPlaces(
        locations: locations,
        rootId: 'world',
      );
      expect(regions.map((region) => region.locationId), ['north', 'kingdom']);
      expect(places.map((place) => place.locationId), [
        'north',
        'kingdom',
        'city',
      ]);
    });

    test('rootId 为空时退化为整棵地点树', () {
      final locations = [
        loc('north', locationTypeContinent),
        loc('city', locationTypeCity),
      ];
      final (regions, places) = deriveMapRegionsAndPlaces(
        locations: locations,
        rootId: null,
      );
      expect(regions.single.locationId, 'north');
      expect(places.map((place) => place.locationId), ['north', 'city']);
    });
  });

  group('mapNameEditDistance', () {
    test('精确与错字', () {
      expect(mapNameEditDistance('寒城', '寒城'), 0);
      expect(mapNameEditDistance('寒城', ' 寒城 '), 0);
      expect(mapNameEditDistance('寒城', '塞城'), 1);
      expect(mapNameEditDistance('寒城', '翡翠城'), greaterThan(1));
    });
  });

  group('MapStudioSettings', () {
    test('唯一地图图片字段与未知键往返一致', () {
      final map = <String, dynamic>{
        'studioVersion': 3,
        'image': 'images/maps/m1/map-v3.webp',
        'canvasWidth': 3072,
        'canvasHeight': 1728,
        'unmatchedLocationIds': ['p9'],
        'someLegacyKey': 42,
      };
      final settings = MapStudioSettings.fromMap(map);
      expect(settings.version, 3);
      expect(settings.hasImage, isTrue);
      expect(settings.image, 'images/maps/m1/map-v3.webp');
      expect(settings.extra['someLegacyKey'], 42);
      final roundTrip = MapStudioSettings.fromMap(settings.toJson());
      expect(roundTrip.version, 3);
      expect(roundTrip.image, settings.image);
      expect(roundTrip.extra['someLegacyKey'], 42);
    });
  });

  group('MapPlaceNameReader 响应解析', () {
    test('精确匹配与错字兜底、未找到进 unresolved', () {
      final content = jsonEncode({
        'matches': [
          {'name': '寒城', 'x': 0.48, 'y': 0.38},
          {'name': '骑士港', 'x': 0.19, 'y': 0.67},
          {'name': '翡翠城', 'x': 0.49, 'y': 0.86},
        ],
        'unmatched': ['观星台'],
      });
      final result = MapPlaceNameReader.parseResponse(content, [
        const MapPlaceNameCandidate(locationId: 'p1', name: '寒城'),
        const MapPlaceNameCandidate(locationId: 'p2', name: '骑士港'),
        const MapPlaceNameCandidate(locationId: 'p3', name: '翡翠诚'),
        const MapPlaceNameCandidate(locationId: 'p4', name: '观星台'),
      ]);
      expect(result.matches.length, 3);
      expect(
        result.matches.map((match) => match.locationId),
        containsAll(['p1', 'p2', 'p3']),
      );
      expect(result.unresolved, ['观星台']);
    });
  });
}
