// 职责: 保存地图地名识别快照，核对地点清单后复用成功结果。
// 关联文件:
//   lib/shared/models/map_studio_models.dart
//   lib/shared/services/generate_map_orchestrator.dart
//   lib/shared/services/image_library_service.dart
import 'map_studio_models.dart';

/// 快照存放在所属图片资产的 metadata 中，图片字节不会变化，因此只核对地点清单。
class MapPlaceRecognition {
  const MapPlaceRecognition({required this.places, required this.result});

  final List<MapPlaceNameCandidate> places;
  final MapPlaceReadResult result;

  bool matchesInput(List<MapPlaceNameCandidate> candidates) {
    if (places.length != candidates.length) {
      return false;
    }
    for (var i = 0; i < places.length; i++) {
      if (places[i].locationId != candidates[i].locationId ||
          places[i].name != candidates[i].name) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'places': [
      for (final place in places)
        {'location_id': place.locationId, 'name': place.name},
    ],
    'matches': [
      for (final match in result.matches)
        {
          'location_id': match.locationId,
          'requested_name': match.requestedName,
          'matched_name': match.matchedName,
          'x': match.x,
          'y': match.y,
        },
    ],
    'unresolved': result.unresolved,
  };

  factory MapPlaceRecognition.fromJson(Map<String, dynamic> json) {
    return MapPlaceRecognition(
      places: [
        for (final place in json['places'] as List)
          MapPlaceNameCandidate(
            locationId: place['location_id'] as String,
            name: place['name'] as String,
          ),
      ],
      result: MapPlaceReadResult(
        matches: [
          for (final match in json['matches'] as List)
            MapPlaceMatch(
              locationId: match['location_id'] as String,
              requestedName: match['requested_name'] as String,
              matchedName: match['matched_name'] as String,
              x: (match['x'] as num).toDouble(),
              y: (match['y'] as num).toDouble(),
            ),
        ],
        unresolved: List<String>.from(json['unresolved'] as List),
      ),
    );
  }
}
