// 职责: Document 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';
import '../../third/form/flutter_hook_form.dart';

export '../database/novel_content_database.dart'
    show Document, Documents, DocumentsCompanion;

enum DocumentEditFields implements FieldSchema {
  type(validators: [RequiredValidator()], initialValue: ''),
  title(validators: [RequiredValidator()]),
  content(initialValue: ''),
  status(initialValue: 'active'),
  tags(initialValue: '');

  const DocumentEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension DocumentX on Document {
  bool get isEmpty => content.trim().isEmpty;

  bool get isActive => status == 'active';

  bool get isArchived => status == 'archived';

  String get contentSummary => truncateUtf16Safe(content.trim(), 200);

  List<String> get tagList => tags.isEmpty
      ? const []
      : tags
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
}

extension DocumentListX on List<Document> {
  List<Document> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Document> get enabled =>
      where((d) => d.deletedAt == notDeletedSentinel).toList();

  List<Document> get folders => where((d) => d.isFolder).toList();

  List<Document> get files => where((d) => !d.isFolder).toList();
}
