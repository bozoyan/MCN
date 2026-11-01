// 职责: 通用 Condition 构建器 — 将三层条件组 UI 编辑为 condition map。
// 关联文件:
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/conditions/condition_evaluator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/condition.json
//   assets/translations/zh-CN/condition.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../components/reveric_select.dart';
import '../components/reveric_text_field.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

enum ConditionFieldValueType {
  string,
  number,
  boolean,
  list,
  object,
  nullValue,
}

class ConditionFieldDefinition {
  const ConditionFieldDefinition({
    required this.key,
    required this.label,
    required this.valueType,
    required this.operators,
    required this.defaultRightText,
  });

  final String key;
  final String label;
  final ConditionFieldValueType valueType;
  final List<String> operators;
  final String defaultRightText;

  Object? parseValue(String value) {
    final trimmed = value.trim();
    return switch (valueType) {
      ConditionFieldValueType.number => num.tryParse(trimmed) ?? 0,
      ConditionFieldValueType.boolean => trimmed == 'true',
      ConditionFieldValueType.list =>
        trimmed
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      ConditionFieldValueType.object => trimmed,
      ConditionFieldValueType.nullValue => null,
      ConditionFieldValueType.string => trimmed,
    };
  }
}

class ConditionBuilder extends StatelessWidget {
  const ConditionBuilder({
    super.key,
    required this.condition,
    required this.fields,
    required this.onChanged,
  }) : assert(fields.length > 0);

  final Map<String, dynamic> condition;
  final List<ConditionFieldDefinition> fields;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = _ParsedConditionTree.from(condition, fields);
    if (!_deepEquals(condition, parsed.map)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(parsed.map);
      });
    }
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: RevericSpacing.sm,
          runSpacing: RevericSpacing.sm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ConditionBadge(label: context.t(LocaleKeys.conditionAnyGroups)),
            OutlinedButton.icon(
              key: const ValueKey('condition_add_group_button'),
              onPressed: () => onChanged(parsed.addGroup().map),
              icon: RevericIcon(
                RevericIcons.add,
                size: 16,
                color: colors.textSecondary,
              ),
              label: Text(context.t(LocaleKeys.conditionAddGroup)),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        Text(
          context.t(LocaleKeys.conditionHint),
          style: typo.uiSmall.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.lg),
        for (final entry in parsed.groups.asMap().entries) ...[
          _ConditionGroupCard(
            groupIndex: entry.key,
            group: entry.value,
            canDelete: parsed.groups.length > 1,
            onAddCompare: () => onChanged(
              parsed.updateGroup(entry.key, entry.value.addCompare()).map,
            ),
            onDelete: () => onChanged(parsed.removeGroup(entry.key).map),
            onChanged: (group) =>
                onChanged(parsed.updateGroup(entry.key, group).map),
          ),
          if (entry.key != parsed.groups.length - 1)
            const SizedBox(height: RevericSpacing.lg),
        ],
      ],
    );
  }
}

class _ConditionGroupCard extends StatelessWidget {
  const _ConditionGroupCard({
    required this.groupIndex,
    required this.group,
    required this.canDelete,
    required this.onAddCompare,
    required this.onDelete,
    required this.onChanged,
  });

  final int groupIndex;
  final _ParsedConditionGroup group;
  final bool canDelete;
  final VoidCallback onAddCompare;
  final VoidCallback onDelete;
  final ValueChanged<_ParsedConditionGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      key: ValueKey('condition_group_$groupIndex'),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: RevericSpacing.sm,
                  runSpacing: RevericSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      context.t(
                        LocaleKeys.conditionGroupTitle,
                        namedArgs: {'index': '${groupIndex + 1}'},
                      ),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    _ConditionBadge(
                      label: context.t(LocaleKeys.conditionAllItems),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                key: ValueKey('condition_add_compare_$groupIndex'),
                onPressed: onAddCompare,
                icon: RevericIcon(
                  RevericIcons.add,
                  size: 15,
                  color: colors.textSecondary,
                ),
                label: Text(context.t(LocaleKeys.conditionAddCompare)),
              ),
              IconButton(
                tooltip: context.t(LocaleKeys.commonDelete),
                onPressed: canDelete ? onDelete : null,
                icon: RevericIcon(
                  RevericIcons.delete_outline,
                  size: 16,
                  color: canDelete ? colors.deletionBorder : colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          for (final entry in group.compares.asMap().entries) ...[
            _CompareConditionRow(
              groupIndex: groupIndex,
              compareIndex: entry.key,
              compare: entry.value,
              canDelete: group.compares.length > 1,
              onChanged: (compare) =>
                  onChanged(group.updateCompare(entry.key, compare)),
              onDelete: () => onChanged(group.removeCompare(entry.key)),
            ),
            if (entry.key != group.compares.length - 1)
              const SizedBox(height: RevericSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _CompareConditionRow extends StatelessWidget {
  const _CompareConditionRow({
    required this.groupIndex,
    required this.compareIndex,
    required this.compare,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  final int groupIndex;
  final int compareIndex;
  final _ParsedCompareCondition compare;
  final bool canDelete;
  final ValueChanged<_ParsedCompareCondition> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final field = compare.field(compare.leftPath);
    final operators = field.operators;
    final operator = operators.contains(compare.operator)
        ? compare.operator
        : operators.first;
    final current = operator == compare.operator
        ? compare
        : compare.copyWith(operator: operator);
    final usesRightValue = !_rightlessOperators.contains(current.operator);

    return Container(
      key: ValueKey('condition_compare_${groupIndex}_$compareIndex'),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _QueryDropdown<String>(
                  fieldKey: _fieldKey(groupIndex, compareIndex),
                  label: context.t(LocaleKeys.conditionLeft),
                  value: field.key,
                  items: compare.fields.map((item) => item.key).toList(),
                  labelFor: (value) => compare.field(value).label,
                  onChanged: (value) {
                    final nextField = compare.field(value);
                    onChanged(
                      current.copyWith(
                        leftPath: nextField.key,
                        operator: nextField.operators.first,
                        rightText: nextField.defaultRightText,
                      ),
                    );
                  },
                ),
                const SizedBox(height: RevericSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _QueryDropdown<String>(
                        fieldKey: _operatorKey(groupIndex, compareIndex),
                        label: context.t(LocaleKeys.conditionOperator),
                        value: current.operator,
                        items: operators,
                        labelFor: (value) => _operatorLabel(context, value),
                        onChanged: (value) => onChanged(
                          current.copyWith(operator: value ?? operators.first),
                        ),
                      ),
                    ),
                    if (usesRightValue) ...[
                      const SizedBox(width: RevericSpacing.lg),
                      Expanded(
                        child: _QueryTextField(
                          fieldKey: _rightKey(groupIndex, compareIndex),
                          label: context.t(LocaleKeys.conditionRight),
                          initialValue: current.rightText,
                          onChanged: (value) =>
                              onChanged(current.copyWith(rightText: value)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          IconButton(
            tooltip: context.t(LocaleKeys.commonDelete),
            onPressed: canDelete ? onDelete : null,
            icon: RevericIcon(
              RevericIcons.delete_outline,
              size: 16,
              color: canDelete ? colors.deletionBorder : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.sm,
          vertical: RevericSpacing.xxs,
        ),
        child: Text(label, style: typo.uiTiny.copyWith(color: colors.accent)),
      ),
    );
  }
}

class _ParsedConditionTree {
  const _ParsedConditionTree({required this.groups, required this.fields});

  final List<_ParsedConditionGroup> groups;
  final List<ConditionFieldDefinition> fields;

  Map<String, dynamic> get map {
    return {
      'type': 'any',
      'items': groups.map((group) => group.map).toList(growable: false),
    };
  }

  _ParsedConditionTree addGroup() {
    return _ParsedConditionTree(
      fields: fields,
      groups: [...groups, _defaultGroup(fields)],
    );
  }

  _ParsedConditionTree removeGroup(int index) {
    final next = [
      for (var i = 0; i < groups.length; i++)
        if (i != index) groups[i],
    ];
    return _ParsedConditionTree(
      fields: fields,
      groups: next.isEmpty ? [_defaultGroup(fields)] : next,
    );
  }

  _ParsedConditionTree updateGroup(int index, _ParsedConditionGroup group) {
    return _ParsedConditionTree(
      fields: fields,
      groups: [
        for (var i = 0; i < groups.length; i++) i == index ? group : groups[i],
      ],
    );
  }

  static _ParsedConditionTree from(
    Map<String, dynamic> condition,
    List<ConditionFieldDefinition> fields,
  ) {
    final type = condition['type']?.toString();
    if (type == 'any') {
      final rawItems = condition['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        return _ParsedConditionTree(
          fields: fields,
          groups: rawItems
              .whereType<Map>()
              .map((item) => _ParsedConditionGroup.from(item, fields))
              .toList(growable: false),
        )._ensureNotEmpty();
      }
    }
    return _ParsedConditionTree(
      fields: fields,
      groups: [_defaultGroup(fields)],
    );
  }

  _ParsedConditionTree _ensureNotEmpty() {
    return groups.isEmpty
        ? _ParsedConditionTree(fields: fields, groups: [_defaultGroup(fields)])
        : this;
  }
}

class _ParsedConditionGroup {
  const _ParsedConditionGroup({required this.compares, required this.fields});

  final List<_ParsedCompareCondition> compares;
  final List<ConditionFieldDefinition> fields;

  Map<String, dynamic> get map {
    return {
      'type': 'all',
      'items': compares.map((compare) => compare.map).toList(growable: false),
    };
  }

  _ParsedConditionGroup addCompare() {
    return _ParsedConditionGroup(
      fields: fields,
      compares: [...compares, _defaultCompare(fields)],
    );
  }

  _ParsedConditionGroup removeCompare(int index) {
    final next = [
      for (var i = 0; i < compares.length; i++)
        if (i != index) compares[i],
    ];
    return _ParsedConditionGroup(
      fields: fields,
      compares: next.isEmpty ? [_defaultCompare(fields)] : next,
    );
  }

  _ParsedConditionGroup updateCompare(
    int index,
    _ParsedCompareCondition compare,
  ) {
    return _ParsedConditionGroup(
      fields: fields,
      compares: [
        for (var i = 0; i < compares.length; i++)
          i == index ? compare : compares[i],
      ],
    );
  }

  static _ParsedConditionGroup from(
    Map<dynamic, dynamic> condition,
    List<ConditionFieldDefinition> fields,
  ) {
    final type = condition['type']?.toString();
    if (type == 'all') {
      final rawItems = condition['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        return _ParsedConditionGroup(
          fields: fields,
          compares: rawItems
              .whereType<Map>()
              .map((item) => _ParsedCompareCondition.from(item, fields))
              .toList(growable: false),
        )._ensureNotEmpty();
      }
    }
    return _defaultGroup(fields);
  }

  _ParsedConditionGroup _ensureNotEmpty() {
    return compares.isEmpty
        ? _ParsedConditionGroup(
            fields: fields,
            compares: [_defaultCompare(fields)],
          )
        : this;
  }
}

class _ParsedCompareCondition {
  const _ParsedCompareCondition({
    required this.leftPath,
    required this.operator,
    required this.rightText,
    required this.fields,
  });

  final String leftPath;
  final String operator;
  final String rightText;
  final List<ConditionFieldDefinition> fields;

  Map<String, dynamic> get map {
    final field = this.field(leftPath);
    final op = field.operators.contains(operator)
        ? operator
        : field.operators.first;
    final result = <String, dynamic>{
      'type': 'compare',
      'left': {'field': field.key},
      'op': op,
    };
    if (!_rightlessOperators.contains(op)) {
      result['right'] = {'value': field.parseValue(rightText)};
    }
    return result;
  }

  _ParsedCompareCondition copyWith({
    String? leftPath,
    String? operator,
    String? rightText,
  }) {
    return _ParsedCompareCondition(
      leftPath: leftPath ?? this.leftPath,
      operator: operator ?? this.operator,
      rightText: rightText ?? this.rightText,
      fields: fields,
    );
  }

  ConditionFieldDefinition field(String? key) {
    for (final field in fields) {
      if (field.key == key) {
        return field;
      }
    }
    return fields.first;
  }

  static _ParsedCompareCondition from(
    Map<dynamic, dynamic> condition,
    List<ConditionFieldDefinition> fields,
  ) {
    final rawLeft = condition['left'];
    final left = rawLeft is Map
        ? (rawLeft['field'] ?? rawLeft['path'])?.toString()
        : null;
    final field = _conditionField(left, fields);
    final rawOperator = condition['op']?.toString();
    final operator = field.operators.contains(rawOperator)
        ? rawOperator!
        : field.operators.first;
    final rawRight = condition['right'];
    final right = rawRight is Map && rawRight.containsKey('value')
        ? rawRight['value']?.toString()
        : field.defaultRightText;
    return _ParsedCompareCondition(
      leftPath: field.key,
      operator: operator,
      rightText: right ?? '',
      fields: fields,
    );
  }
}

class _QueryTextField extends HookWidget {
  const _QueryTextField({
    required this.fieldKey,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialValue);
    useEffect(() {
      if (controller.text != initialValue) {
        controller.text = initialValue;
      }
      return null;
    }, [initialValue]);
    return RevericTextField(
      fieldKey: fieldKey,
      controller: controller,
      label: label,
      onChanged: onChanged,
    );
  }
}

class _QueryDropdown<T> extends StatelessWidget {
  const _QueryDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) labelFor;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RevericSelect<T>(
      key: fieldKey,
      label: label,
      value: value,
      items: [
        for (final item in items)
          RevericSelectItem<T>(value: item, label: labelFor(item)),
      ],
      onChanged: onChanged,
    );
  }
}

const _rightlessOperators = {'is_empty', 'is_not_empty'};

/// 校验条件树：任一「使用右值的比较项」右值为空则返回 true。
/// 供保存前校验使用，避免空右值条件被静默保存（desktop / mobile 共用）。
bool conditionHasEmptyRightValue(Map<String, dynamic> condition) {
  final groups = condition['items'];
  if (groups is! List) {
    return false;
  }
  for (final group in groups) {
    if (group is! Map) {
      continue;
    }
    final compares = group['items'];
    if (compares is! List) {
      continue;
    }
    for (final compare in compares) {
      if (compare is! Map) {
        continue;
      }
      final op = compare['op']?.toString();
      if (op == null || _rightlessOperators.contains(op)) {
        continue;
      }
      final right = compare['right'];
      final value = right is Map ? right['value'] : null;
      if (_isEmptyConditionValue(value)) {
        return true;
      }
    }
  }
  return false;
}

bool _isEmptyConditionValue(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is String) {
    return value.trim().isEmpty;
  }
  if (value is List) {
    return value.isEmpty;
  }
  return false;
}

String _operatorLabel(BuildContext context, String operator) {
  return context.t(
    switch (operator) {
      'eq' => LocaleKeys.conditionOperatorEq,
      'neq' => LocaleKeys.conditionOperatorNeq,
      'gt' => LocaleKeys.conditionOperatorGt,
      'gte' => LocaleKeys.conditionOperatorGte,
      'lt' => LocaleKeys.conditionOperatorLt,
      'lte' => LocaleKeys.conditionOperatorLte,
      'contains' => LocaleKeys.conditionOperatorContains,
      'starts_with' => LocaleKeys.conditionOperatorStartsWith,
      'ends_with' => LocaleKeys.conditionOperatorEndsWith,
      'is_empty' => LocaleKeys.conditionOperatorIsEmpty,
      'is_not_empty' => LocaleKeys.conditionOperatorIsNotEmpty,
      _ => LocaleKeys.conditionOperatorUnknown,
    },
    namedArgs: {'op': operator},
  );
}

ConditionFieldDefinition _conditionField(
  String? key,
  List<ConditionFieldDefinition> fields,
) {
  for (final field in fields) {
    if (field.key == key) {
      return field;
    }
  }
  return fields.first;
}

_ParsedConditionGroup _defaultGroup(List<ConditionFieldDefinition> fields) {
  return _ParsedConditionGroup(
    fields: fields,
    compares: [_defaultCompare(fields)],
  );
}

_ParsedCompareCondition _defaultCompare(List<ConditionFieldDefinition> fields) {
  final field = fields.first;
  return _ParsedCompareCondition(
    leftPath: field.key,
    operator: field.operators.first,
    rightText: field.defaultRightText,
    fields: fields,
  );
}

Key _fieldKey(int groupIndex, int compareIndex) {
  if (groupIndex == 0 && compareIndex == 0) {
    return const ValueKey('condition_left_field');
  }
  return ValueKey('condition_field_${groupIndex}_$compareIndex');
}

Key _operatorKey(int groupIndex, int compareIndex) {
  if (groupIndex == 0 && compareIndex == 0) {
    return const ValueKey('condition_operator_field');
  }
  return ValueKey('condition_operator_${groupIndex}_$compareIndex');
}

Key _rightKey(int groupIndex, int compareIndex) {
  if (groupIndex == 0 && compareIndex == 0) {
    return const ValueKey('condition_right_field');
  }
  return ValueKey('condition_right_${groupIndex}_$compareIndex');
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (!_deepEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}
