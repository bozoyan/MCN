// 职责: 解析和验证版本化集合条件树，保留不支持或损坏文档的原始文本。
// 关联文件:
//   lib/shared/models/collections/fields.dart
//   lib/shared/database/type_converters.dart
//   lib/shared/database/queries/collection_filter.dart
import 'dart:convert';
import 'fields.dart';

enum CollectionFilterStatus { valid, unsupported, damaged }

sealed class CollectionCondition {
  const CollectionCondition();
  Map<String, Object?> toJson();
}

class CollectionGroup extends CollectionCondition {
  CollectionGroup(this.any, Iterable<CollectionCondition> items)
    : items = List.unmodifiable(items);
  final bool any;
  final List<CollectionCondition> items;
  @override
  Map<String, Object?> toJson() => {
    'type': any ? 'any' : 'all',
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class CollectionNot extends CollectionCondition {
  const CollectionNot(this.item);
  final CollectionCondition item;
  @override
  Map<String, Object?> toJson() => {'type': 'not', 'item': item.toJson()};
}

class CollectionCompare extends CollectionCondition {
  const CollectionCompare(this.field, this.op, [this.value]);
  final String field;
  final String op;
  final Object? value;
  @override
  Map<String, Object?> toJson() => {
    'type': 'compare',
    'left': {'field': field},
    'op': op,
    if (op != 'is_empty' && op != 'is_not_empty') 'right': {'value': value},
  };
}

class CollectionFilter {
  const CollectionFilter._(this.raw, this.status, this.root, this.reason);
  final String raw;
  final CollectionFilterStatus status;
  final CollectionCondition? root;
  final String? reason;
  bool get isValid => status == CollectionFilterStatus.valid;

  factory CollectionFilter.fromRoot(
    CollectionCondition root, {
    Map<String, CollectionField> fields = collectionFields,
  }) {
    final result = CollectionFilter.parse(
      jsonEncode({'version': 1, 'root': root.toJson()}),
      fields: fields,
    );
    result.requireValid();
    return result;
  }

  factory CollectionFilter.parse(
    String raw, {
    Map<String, CollectionField> fields = collectionFields,
  }) {
    try {
      final document = _object(jsonDecode(raw), r'$');
      _keys(document, {'version', 'root'}, r'$');
      if (document['version'] is! int) {
        throw const FormatException(r'$.version: expected integer');
      }
      if (document['version'] != 1) {
        throw const _Unsupported(r'$.version: unsupported version');
      }
      var count = 0;
      CollectionCondition read(Object? input, String path, int depth) {
        count++;
        if (depth > 3 || count > 50) {
          throw FormatException('$path: maximum depth 3 and 50 nodes');
        }
        final node = _object(input, path);
        switch (node['type']) {
          case 'all' || 'any':
            _keys(node, {'type', 'items'}, path);
            final items = node['items'];
            if (items is! List || items.isEmpty) {
              throw FormatException('$path.items: expected non-empty array');
            }
            return CollectionGroup(node['type'] == 'any', [
              for (var i = 0; i < items.length; i++)
                read(items[i], '$path.items[$i]', depth + 1),
            ]);
          case 'not':
            _keys(node, {'type', 'item'}, path);
            return CollectionNot(read(node['item'], '$path.item', depth + 1));
          case 'compare':
            final op = node['op'];
            if (op is! String) {
              throw FormatException('$path.op: expected string');
            }
            final empty = op == 'is_empty' || op == 'is_not_empty';
            _keys(node, {'type', 'left', 'op', if (!empty) 'right'}, path);
            final left = _object(node['left'], '$path.left');
            _keys(left, {'field'}, '$path.left');
            final id = left['field'];
            if (id is! String) {
              throw FormatException('$path.left.field: expected string');
            }
            final field = fields[id];
            if (field == null) {
              throw _Unsupported('$path.left.field: unsupported field $id');
            }
            if (!field.operators.contains(op)) {
              throw _Unsupported('$path.op: unsupported operator $op');
            }
            Object? value;
            if (!empty) {
              final right = _object(node['right'], '$path.right');
              _keys(right, {'value'}, '$path.right');
              value = right['value'];
              if (!field.accepts(value)) {
                throw FormatException(
                  '$path.right.value: invalid ${field.type.name}',
                );
              }
            }
            return CollectionCompare(id, op, value);
          default:
            throw _Unsupported('$path.type: unsupported node');
        }
      }

      return CollectionFilter._(
        raw,
        CollectionFilterStatus.valid,
        read(document['root'], r'$.root', 1),
        null,
      );
    } on _Unsupported catch (error) {
      return CollectionFilter._(
        raw,
        CollectionFilterStatus.unsupported,
        null,
        error.message,
      );
    } on FormatException catch (error) {
      return CollectionFilter._(
        raw,
        CollectionFilterStatus.damaged,
        null,
        error.message,
      );
    }
  }

  void requireValid() {
    if (!isValid) {
      throw FormatException(reason ?? 'Invalid collection filter');
    }
  }
}

Map<String, dynamic> _object(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$path: expected object');
  }
  return value;
}

void _keys(Map<String, dynamic> map, Set<String> keys, String path) {
  if (map.length != keys.length || !map.keys.every(keys.contains)) {
    throw FormatException('$path: missing or unknown properties');
  }
}

class _Unsupported implements Exception {
  const _Unsupported(this.message);
  final String message;
}
