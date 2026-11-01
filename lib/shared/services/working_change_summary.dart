// 职责: 按字段聚合原始变更为不可变审阅快照，并计算文本净变化与摘要标签。
// 关联文件:
//   lib/desktop/widgets/ai/diff/pending_changes_summary_card.dart
//   lib/desktop/widgets/history/change_history_panel.dart
//   lib/shared/services/working_overlay.dart
import 'package:flutter/foundation.dart' show listEquals;
import '../utils/text_unit_count.dart';
import '../utils/resource_path.dart';
import '../database/novel_content_database.dart';

/// 计算两段文本按统一"文本单元"口径的新增 / 删除数。
({int added, int removed}) lineDelta(String? oldText, String? newText) {
  return countTextUnitDelta(oldText, newText);
}

/// 改动类型标签（新增/改写/扩写/删减）。
///
/// - create → 新增
/// - 仅 new（原为空）→ 扩写；仅 old（改没了）→ 删减
/// - old/new 均非空（整段改写常态）→ 按净字数增减带 margin 细分：
///   显著变长 → 扩写，显著变短 → 删减，否则 → 改写
const changeTypeCreate = 'create';
const changeTypeRewrite = 'rewrite';
const changeTypeExpand = 'expand';
const changeTypeTrim = 'trim';

String resolveChangeTypeLabel(
  String changeType,
  String? oldText,
  String? newText,
) {
  if (changeType == changeTypeCreate) {
    return changeTypeCreate;
  }
  final hasOld = (oldText ?? '').isNotEmpty;
  final hasNew = (newText ?? '').isNotEmpty;
  if (!hasOld && hasNew) {
    return changeTypeExpand;
  }
  if (hasOld && !hasNew) {
    return changeTypeTrim;
  }
  if (!hasOld && !hasNew) {
    return changeTypeRewrite;
  }
  // 均非空：按净字数判定，margin 取原文 15%（下限 10 文本单元），避免把微调误判为扩/删。
  final before = countTextUnits(oldText ?? '');
  final delta = countTextUnitDelta(oldText, newText);
  final net = delta.added - delta.removed;
  final margin = (before * 0.15).round().clamp(10, 1 << 30);
  if (net > margin) {
    return changeTypeExpand;
  }
  if (net < -margin) {
    return changeTypeTrim;
  }
  return changeTypeRewrite;
}

/// 从章节创建预览文本里抽取章节标题（兼容“第 N 章: 标题” / “第 N 章 标题”等格式）。
String? extractCreatedChapterTitle(String? previewText) {
  final text = previewText?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  final lines = text.split('\n');
  for (final line in lines.take(6)) {
    final normalized = line.trim();
    if (normalized.isEmpty) continue;
    final match = RegExp(r'^第?\s*\d+\s*章[:：\s]+(.+)$').firstMatch(normalized);
    if (match != null) {
      return match.group(1)?.trim().isNotEmpty == true
          ? match.group(1)!.trim()
          : normalized;
    }
    if (normalized.startsWith('第') && normalized.contains('章')) {
      return normalized;
    }
  }
  return lines.first.trim().isEmpty ? null : lines.first.trim();
}

/// 不可变的字段审阅快照；changes 按落库顺序保留，不能作为合并记录写库。
class WorkingFieldReview {
  WorkingFieldReview({
    required List<WorkingChange> changes,
    required String? currentText,
  }) : changes = List.unmodifiable(changes),
       newText = currentText;

  final List<WorkingChange> changes;
  final String? newText;
  WorkingChange get _first => changes.first;
  String get key => workingChangeFieldKey(_first);
  String get resourcePath => _first.resourcePath;
  String get resourceType => _first.resourceType;
  String? get resourceId => _first.resourceId;
  String? get field => _first.field;
  String get changeType => _first.changeType;
  String? get oldText => _first.oldText;

  /// 这些字段的展示行来自 JSON，不能作为存储文本的行键应用。
  bool get isStructuredField => switch ((resourceType, field)) {
    (
      'screenplay_scenes',
      'elements' || 'events' || 'emotion' || 'interior_exterior',
    ) =>
      true,
    ('characters', 'aliases' || 'behavior_tags' || 'photos') => true,
    ('locations', 'photos') => true,
    ('outlines', 'beats') => true,
    ('production_clips', 'document') => true,
    ('screenplays', 'style_id') => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkingFieldReview &&
      listEquals(changes, other.changes) &&
      newText == other.newText;
  @override
  int get hashCode => Object.hash(Object.hashAll(changes), newText);

  bool get reviewable => changes.every(
    (row) =>
        row.source == 'ai' &&
        (row.status == 'active' || row.status == 'committed'),
  );
}

String workingChangeFieldKey(WorkingChange change) =>
    '${change.resourceType}:${change.resourceId ?? canonicalResourcePath(change.resourcePath)}:${change.field ?? ''}:${change.changeType == 'create' ? 'create' : 'field'}';

List<List<WorkingChange>> groupWorkingChangesByField(
  Iterable<WorkingChange> changes,
  Map<String, int> insertionOrder,
) {
  final sorted = changes.toList()
    ..sort((a, b) => insertionOrder[a.id]!.compareTo(insertionOrder[b.id]!));
  final groups = <String, List<WorkingChange>>{};
  for (final change in sorted) {
    groups.putIfAbsent(workingChangeFieldKey(change), () => []).add(change);
  }
  return groups.values.toList();
}
