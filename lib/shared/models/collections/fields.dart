// 职责: 定义集合条件字段、操作符及严格的字面值校验。
// 关联文件:
//   lib/shared/models/collections/filter.dart
//   lib/shared/database/queries/collection_filter.dart
//   lib/shared/models/content_status.dart
//   lib/shared/models/novel_type.dart
import '../content_status.dart';
import '../novel_type.dart';

enum CollectionValueType { text, enumeration, tags, integer }

class CollectionField {
  const CollectionField(
    this.id,
    this.type,
    this.operators, {
    this.values = const [],
  });
  final String id;
  final CollectionValueType type;
  final Set<String> operators;
  final List<String> values;

  bool accepts(Object? value) => switch (type) {
    CollectionValueType.integer => value is int && value >= 0,
    CollectionValueType.enumeration =>
      value is String && values.contains(value),
    CollectionValueType.text ||
    CollectionValueType.tags => value is String && value.isNotEmpty,
  };
}

const collectionFields = <String, CollectionField>{
  'novel.status': CollectionField(
    'novel.status',
    CollectionValueType.enumeration,
    {'eq', 'neq'},
    values: contentStatuses,
  ),
  'novel.type': CollectionField('novel.type', CollectionValueType.enumeration, {
    'eq',
    'neq',
  }, values: novelTypes),
  'novel.category': CollectionField(
    'novel.category',
    CollectionValueType.text,
    {'eq', 'neq', 'is_empty', 'is_not_empty'},
  ),
  'novel.tags': CollectionField('novel.tags', CollectionValueType.tags, {
    'contains',
    'is_empty',
    'is_not_empty',
  }),
  'novel.title': CollectionField('novel.title', CollectionValueType.text, {
    'eq',
    'contains',
    'starts_with',
    'ends_with',
  }),
  'novel.word_count': CollectionField(
    'novel.word_count',
    CollectionValueType.integer,
    {'eq', 'neq', 'gt', 'gte', 'lt', 'lte'},
  ),
};
