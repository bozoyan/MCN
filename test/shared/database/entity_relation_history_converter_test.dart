// 职责: 验证关系历史 JSON 严格解析，不以空历史掩盖损坏数据。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/models/entity_relation_history.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/type_converters.dart';
import 'package:reveric/shared/models/entity_relation_history.dart';

void main() {
  const converter = RelationStateSnapshotListConverter();
  final baseline = RelationStateSnapshot(
    id: 'stable',
    kind: RelationSnapshotKind.baseline,
    relationType: 'friend',
    status: RelationStatus.active,
    proof: '',
    reason: '',
    recordedAt: DateTime.utc(2026),
  );
  test('round trips legacy empty and complete Unicode snapshots', () {
    expect(converter.fromSql('[]'), isEmpty);
    final encoded = converter.toSql([baseline]);
    expect(converter.fromSql(encoded).single.toJson(), baseline.toJson());
  });
  test(
    'rejects invalid JSON, shape, unknown enums, invalid sequence and duplicate IDs',
    () {
      final valid = baseline.toJson();
      for (final invalid in [
        '{',
        '{}',
        '[null]',
        '[1]',
        jsonEncode([
          {...valid, 'kind': 'correction'},
        ]),
        jsonEncode([
          {...valid, 'status': 'unknown'},
        ]),
        jsonEncode([
          {...valid, 'recorded_at': 'not a date'},
        ]),
        jsonEncode([
          {...valid, 'proof': 12},
        ]),
        jsonEncode([
          {...valid, 'chapter_id': 'c', 'scene_id': 's'},
        ]),
        jsonEncode([valid, valid]),
        jsonEncode([
          {...valid, 'kind': 'change', 'proof': 'p', 'reason': 'r'},
        ]),
      ]) {
        expect(
          () => converter.fromSql(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
      expect(
        () => converter.toSql([baseline, baseline]),
        throwsFormatException,
      );
    },
  );
}
