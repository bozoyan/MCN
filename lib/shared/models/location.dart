// 职责: Location 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';
import '../../third/form/flutter_hook_form.dart';

export '../database/novel_content_database.dart'
    show Location, Locations, LocationsCompanion;

enum LocationEditFields implements FieldSchema {
  name(validators: [RequiredValidator()]),
  description(initialValue: ''),
  type(initialValue: 'generic'),
  status(initialValue: 'active'),
  tags(initialValue: '');

  const LocationEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension LocationX on Location {
  bool get isEmpty => description.trim().isEmpty;

  bool get isActive => status == 'active';

  bool get isArchived => status == 'archived';

  String get descriptionSummary => truncateUtf16Safe(description.trim(), 200);

  List<String> get tagList => tags.isEmpty
      ? const []
      : tags
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
}

extension LocationListX on List<Location> {
  List<Location> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Location> get enabled =>
      where((l) => l.deletedAt == notDeletedSentinel).toList();
}
