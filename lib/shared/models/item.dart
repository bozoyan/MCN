// 职责: Item 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';
import '../../third/form/flutter_hook_form.dart';

export '../database/novel_content_database.dart'
    show Item, Items, ItemsCompanion;

enum ItemEditFields implements FieldSchema {
  type(validators: [RequiredValidator()], initialValue: ''),
  title(validators: [RequiredValidator()]),
  content(initialValue: ''),
  status(initialValue: 'active');

  const ItemEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension ItemX on Item {
  bool get isEmpty => content.trim().isEmpty;

  String get contentSummary => truncateUtf16Safe(content.trim(), 200);
}

extension ItemListX on List<Item> {
  List<Item> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Item> get enabled =>
      where((i) => i.deletedAt == notDeletedSentinel).toList();
}
