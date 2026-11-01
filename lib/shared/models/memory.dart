// 职责: Memory 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/app_database.dart

import '../database/app_database.dart';
import '../utils/utf16_safe_text.dart';
import '../../third/form/flutter_hook_form.dart';

export '../database/app_database.dart' show Memory, Memories, MemoriesCompanion;

enum MemoryEditFields implements FieldSchema {
  category(validators: [RequiredValidator()]),
  content(validators: [RequiredValidator()]),
  priority(initialValue: 'context'),
  source(initialValue: 'manual');

  const MemoryEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension MemoryX on Memory {
  bool get isCore => priority == 'core';

  bool get isContext => priority == 'context';

  bool get isEnabled => enabled;

  String get contentSummary => truncateUtf16Safe(content.trim(), 200);
}

extension MemoryListX on List<Memory> {
  List<Memory> get enabled => where((m) => m.enabled).toList();

  List<Memory> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Memory> get core => enabled.where((m) => m.isCore).toList();

  List<Memory> get context => enabled.where((m) => m.isContext).toList();
}
