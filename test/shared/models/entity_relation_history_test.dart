// 职责: 验证关系快照修正保留身份、原因和记录时间。
// 关联文件:
//   lib/shared/models/entity_relation_history.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/entity_relation_history.dart';

void main() {
  test('correction preserves identity, reason, kind and recording time', () {
    final initial = RelationStateSnapshot(
      id: 'a',
      kind: RelationSnapshotKind.change,
      relationType: 'enemy',
      status: RelationStatus.active,
      proof: '完整依据',
      reason: '原因',
      recordedAt: DateTime.utc(2026),
    );
    final corrected = initial.withState(
      relationType: 'friend',
      status: 'ended',
      proof: 'corrected',
      chapterId: null,
      sceneId: null,
    );
    expect(
      (corrected.id, corrected.kind, corrected.reason, corrected.recordedAt),
      (initial.id, initial.kind, initial.reason, initial.recordedAt),
    );
    expect(corrected.status, RelationStatus.ended);
    expect(corrected.toJson()['recorded_at'], '2026-01-01T00:00:00.000Z');
  });
}
