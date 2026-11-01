// 职责: 定义关系当前摘要、状态快照及历史序列校验。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/services/entity_relations_service.dart

enum RelationStatus { active, ended }

enum RelationSnapshotKind { baseline, change }

class RelationServiceException implements Exception {
  const RelationServiceException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class RelationStateSnapshot {
  const RelationStateSnapshot({
    required this.id,
    required this.kind,
    required this.relationType,
    required this.status,
    required this.proof,
    this.chapterId,
    this.sceneId,
    required this.reason,
    required this.recordedAt,
  });
  final String id;
  final RelationSnapshotKind kind;
  final String relationType;
  final RelationStatus status;
  final String proof;
  final String? chapterId;
  final String? sceneId;
  final String reason;
  final DateTime recordedAt;

  factory RelationStateSnapshot.fromJson(Map<String, dynamic> json) {
    String string(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('Invalid relation snapshot $key');
      }
      return value;
    }

    String? reference(String key) {
      final value = json[key];
      if (value != null && (value is! String || value.isEmpty)) {
        throw FormatException('Invalid relation snapshot $key');
      }
      return value as String?;
    }

    final kind = RelationSnapshotKind.values
        .where((v) => v.name == string('kind'))
        .firstOrNull;
    final status = RelationStatus.values
        .where((v) => v.name == string('status'))
        .firstOrNull;
    final time = DateTime.tryParse(string('recorded_at'));
    if (kind == null || status == null || time == null) {
      throw const FormatException(
        'Invalid relation snapshot kind, status or timestamp',
      );
    }
    final snapshot = RelationStateSnapshot(
      id: string('id'),
      kind: kind,
      relationType: string('relation_type'),
      status: status,
      proof: string('proof'),
      chapterId: reference('chapter_id'),
      sceneId: reference('scene_id'),
      reason: string('reason'),
      recordedAt: time.toUtc(),
    );
    snapshot.validate();
    return snapshot;
  }

  void validate() {
    if (id.trim().isEmpty ||
        relationType.trim().isEmpty ||
        (chapterId != null && sceneId != null) ||
        chapterId == '' ||
        sceneId == '' ||
        (kind == RelationSnapshotKind.change &&
            (reason.trim().isEmpty || proof.trim().isEmpty))) {
      throw const FormatException('Invalid relation snapshot fields');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'relation_type': relationType,
    'status': status.name,
    'proof': proof,
    'chapter_id': chapterId,
    'scene_id': sceneId,
    'reason': reason,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };

  RelationStateSnapshot withState({
    required String relationType,
    required String status,
    required String proof,
    required String? chapterId,
    required String? sceneId,
  }) => RelationStateSnapshot(
    id: id,
    kind: kind,
    relationType: relationType,
    status: RelationStatus.values.byName(status),
    proof: proof,
    chapterId: chapterId,
    sceneId: sceneId,
    reason: reason,
    recordedAt: recordedAt,
  );
}

void validateRelationHistory(List<RelationStateSnapshot> snapshots) {
  final ids = <String>{};
  for (var i = 0; i < snapshots.length; i++) {
    final item = snapshots[i];
    item.validate();
    if (!ids.add(item.id) ||
        (i == 0
            ? item.kind != RelationSnapshotKind.baseline
            : item.kind != RelationSnapshotKind.change)) {
      throw const FormatException('Invalid relation history sequence');
    }
  }
}

/// 当前列投影；不包含历史，避免列表和图谱读取随历史增长。
class RelationSummary {
  const RelationSummary({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.targetType,
    required this.targetId,
    required this.relationType,
    required this.status,
    required this.proof,
    this.chapterId,
    this.sceneId,
    this.properties,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String sourceType;
  final String sourceId;
  final String targetType;
  final String targetId;
  final String relationType;
  final String status;
  final String proof;
  final String? chapterId;
  final String? sceneId;
  final Map<String, dynamic>? properties;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceType': sourceType,
    'sourceId': sourceId,
    'targetType': targetType,
    'targetId': targetId,
    'relationType': relationType,
    'status': status,
    'proof': proof,
    'chapterId': chapterId,
    'sceneId': sceneId,
    'properties': properties,
    'sortOrder': sortOrder,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}
