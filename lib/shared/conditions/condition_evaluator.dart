// 职责: 通用 Condition 求值 — 解析嵌套 condition DSL、字段操作数与类型安全比较。
// 关联文件:

typedef ConditionFieldResolver = Object? Function(String field);

class ConditionPending implements Exception {
  const ConditionPending(this.field);

  final String field;
}

class ConditionEvaluator {
  const ConditionEvaluator._();

  static bool evaluate(
    Map<String, dynamic> condition, {
    required ConditionFieldResolver resolveField,
    int depth = 1,
  }) {
    if (depth > 3) {
      throw StateError('Condition nesting exceeds 3 levels');
    }
    final type = condition['type']?.toString();
    return switch (type) {
      'all' => _conditionItems(condition).every(
        (item) => evaluate(item, resolveField: resolveField, depth: depth + 1),
      ),
      'any' => _conditionItems(condition).any(
        (item) => evaluate(item, resolveField: resolveField, depth: depth + 1),
      ),
      'not' => !evaluate(
        _conditionItem(condition),
        resolveField: resolveField,
        depth: depth + 1,
      ),
      'exists' => _resolveOperand(condition, resolveField) != null,
      'compare' => _compareCondition(condition, resolveField),
      _ => throw StateError('Unsupported condition type: $type'),
    };
  }

  static List<Map<String, dynamic>> _conditionItems(
    Map<String, dynamic> condition,
  ) {
    final rawItems = condition['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw StateError('Condition items must be a non-empty list');
    }
    return rawItems
        .map((rawItem) {
          if (rawItem is! Map) {
            throw StateError('Condition item must be an object');
          }
          return rawItem.map((key, value) => MapEntry(key.toString(), value));
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> _conditionItem(Map<String, dynamic> condition) {
    final rawItem = condition['item'];
    if (rawItem is! Map) {
      throw StateError('Not condition requires item');
    }
    return rawItem.map((key, value) => MapEntry(key.toString(), value));
  }

  static bool _compareCondition(
    Map<String, dynamic> condition,
    ConditionFieldResolver resolveField,
  ) {
    final op = condition['op']?.toString();
    final left = _resolveOperandMap(condition['left'], resolveField);
    if (op == 'is_empty') {
      return _isEmptyValue(left);
    }
    if (op == 'is_not_empty') {
      return !_isEmptyValue(left);
    }
    final right = _resolveOperandMap(condition['right'], resolveField);
    final comparison = _compareValues(left, right);
    return switch (op) {
      'eq' => _valuesEqual(left, right),
      'neq' => !_valuesEqual(left, right),
      'gt' => comparison != null && comparison > 0,
      'gte' => comparison != null && comparison >= 0,
      'lt' => comparison != null && comparison < 0,
      'lte' => comparison != null && comparison <= 0,
      'contains' => _containsValue(left, right),
      'starts_with' => _textValue(left).startsWith(_textValue(right)),
      'ends_with' => _textValue(left).endsWith(_textValue(right)),
      _ => throw StateError('Unsupported condition operator: $op'),
    };
  }

  static Object? _resolveOperandMap(
    Object? raw,
    ConditionFieldResolver resolveField,
  ) {
    if (raw is! Map) {
      throw StateError('Condition operand must be an object');
    }
    final operand = raw.map((key, value) => MapEntry(key.toString(), value));
    if (operand.containsKey('value')) {
      return operand['value'];
    }
    return _resolveOperand(operand, resolveField);
  }

  static Object? _resolveOperand(
    Map<String, dynamic> operand,
    ConditionFieldResolver resolveField,
  ) {
    final field = (operand['field'] ?? operand['path'])?.toString();
    if (field == null || field.isEmpty) {
      throw StateError('Condition field is required');
    }
    return resolveField(field);
  }

  static bool _valuesEqual(Object? left, Object? right) {
    if (left == right) {
      return true;
    }
    if (left is num || right is num) {
      final leftNumber = _numberValue(left);
      final rightNumber = _numberValue(right);
      return leftNumber != null &&
          rightNumber != null &&
          leftNumber == rightNumber;
    }
    if (left is bool || right is bool) {
      final leftBoolean = _booleanValue(left);
      final rightBoolean = _booleanValue(right);
      return leftBoolean != null &&
          rightBoolean != null &&
          leftBoolean == rightBoolean;
    }
    if (left is DateTime && right is DateTime) {
      return left.toUtc().isAtSameMomentAs(right.toUtc());
    }
    if (left is DateTime || right is DateTime) {
      final leftDateTime = _dateTimeValue(left);
      final rightDateTime = _dateTimeValue(right);
      return leftDateTime != null &&
          rightDateTime != null &&
          leftDateTime.toUtc().isAtSameMomentAs(rightDateTime.toUtc());
    }
    if (left is Iterable && right is Iterable) {
      final leftItems = left.toList(growable: false);
      final rightItems = right.toList(growable: false);
      if (leftItems.length != rightItems.length) {
        return false;
      }
      for (var index = 0; index < leftItems.length; index++) {
        if (!_valuesEqual(leftItems[index], rightItems[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_valuesEqual(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  static int? _compareValues(Object? left, Object? right) {
    if (left is DateTime || right is DateTime) {
      final leftDateTime = _dateTimeValue(left);
      final rightDateTime = _dateTimeValue(right);
      if (leftDateTime != null && rightDateTime != null) {
        return leftDateTime.toUtc().compareTo(rightDateTime.toUtc());
      }
      return null;
    }
    final leftNumber = _numberValue(left);
    final rightNumber = _numberValue(right);
    if (leftNumber == null || rightNumber == null) {
      return null;
    }
    return leftNumber.compareTo(rightNumber);
  }

  static bool _containsValue(Object? left, Object? right) {
    if (left is String) {
      return left.contains(_textValue(right));
    }
    if (left is Iterable) {
      return left.any((item) => _valuesEqual(item, right));
    }
    if (left is Map) {
      return left.keys.any((key) => _valuesEqual(key, right));
    }
    if (left == null) {
      return false;
    }
    return _textValue(left).contains(_textValue(right));
  }

  static bool _isEmptyValue(Object? value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.isEmpty;
    }
    if (value is Iterable) {
      return value.isEmpty;
    }
    if (value is Map) {
      return value.isEmpty;
    }
    return false;
  }

  static num? _numberValue(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value.trim());
    }
    return null;
  }

  static bool? _booleanValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return switch (value.trim().toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    }
    return null;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  static String _textValue(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value.toString();
  }
}
