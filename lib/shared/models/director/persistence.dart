// 职责: 定义导演编辑器与调用方之间的保存和版本历史回调契约。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/session.dart
import 'document.dart';

class DirectorRevision {
  const DirectorRevision({
    required this.id,
    required this.savedAt,
    this.savedDocument,
  });
  final String id;
  final DateTime savedAt;

  /// 自动保存回调实际落库的文档；普通快照保存省略时使用调用时的文档。
  final DirectorDocument? savedDocument;
}

typedef DirectorSave =
    Future<DirectorRevision?> Function(DirectorDocument document);

class DirectorHistory {
  const DirectorHistory({required this.list, required this.load});
  final Future<List<DirectorRevision>> Function() list;
  final Future<DirectorDocument> Function(String revisionId) load;
}
