// 职责: WorkingChange 模型导出与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';

export '../database/novel_content_database.dart'
    show WorkingChange, WorkingChanges, WorkingChangesCompanion;

extension WorkingChangeX on WorkingChange {
  bool get isActive => status == 'active';

  bool get isCommitted => status == 'committed';

  bool get isReverted => status == 'reverted';

  bool get hasDiff => oldText != null || newText != null;

  String get displaySummary {
    final trimmed = summary.trim();
    if (trimmed.isEmpty) return resourcePath;
    return truncateUtf16Safe(trimmed, 80);
  }
}

extension WorkingChangeListX on List<WorkingChange> {
  List<WorkingChange> get active =>
      where((w) => w.isActive).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<WorkingChange> get committed =>
      where((w) => w.isCommitted).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
