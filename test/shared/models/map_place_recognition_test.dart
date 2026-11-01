import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/map_place_recognition.dart';
import 'package:reveric/shared/models/map_studio_models.dart';

void main() {
  test('persisted coordinates only apply to the same locations', () {
    const places = [MapPlaceNameCandidate(locationId: 'city', name: 'City')];
    final snapshot = MapPlaceRecognition(
      places: places,
      result: const MapPlaceReadResult(
        matches: [
          MapPlaceMatch(
            locationId: 'city',
            requestedName: 'City',
            matchedName: 'City',
            x: 0.25,
            y: 0.75,
          ),
        ],
        unresolved: [],
      ),
    );
    final restored = MapPlaceRecognition.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );
    expect(restored.matchesInput(places), isTrue);
    expect(restored.result.matches.single.x, 0.25);
    expect(
      restored.matchesInput(const [
        MapPlaceNameCandidate(locationId: 'city', name: 'Renamed city'),
      ]),
      isFalse,
    );
    expect(
      restored.matchesInput(const [
        MapPlaceNameCandidate(locationId: 'replacement', name: 'City'),
      ]),
      isFalse,
      reason: 'Recreated places must not receive a deleted location ID',
    );
    expect(restored.matchesInput(const []), isFalse);
    expect(
      restored.matchesInput(const [
        ...places,
        MapPlaceNameCandidate(locationId: 'new', name: 'New city'),
      ]),
      isFalse,
    );
  });
}
