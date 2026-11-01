// 职责: 通用 Condition Evaluator 测试 — 验证独立 condition DSL 的求值行为。
// 关联文件:
//   lib/shared/conditions/condition_evaluator.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/conditions/condition_evaluator.dart';

void main() {
  group('ConditionEvaluator', () {
    test('evaluates nested boolean conditions with caller-provided fields', () {
      final result = ConditionEvaluator.evaluate(
        const {
          'type': 'any',
          'items': [
            {
              'type': 'all',
              'items': [
                {
                  'type': 'compare',
                  'left': {'field': 'ticket.status'},
                  'op': 'eq',
                  'right': {'value': 'open'},
                },
                {
                  'type': 'compare',
                  'left': {'field': 'ticket.priority'},
                  'op': 'gte',
                  'right': {'value': 3},
                },
              ],
            },
          ],
        },
        resolveField: (field) => switch (field) {
          'ticket.status' => 'open',
          'ticket.priority' => 4,
          _ => throw StateError('unknown field: $field'),
        },
      );

      expect(result, isTrue);
    });

    test('rejects nesting deeper than 3', () {
      expect(
        () => ConditionEvaluator.evaluate(const {
          'type': 'not',
          'item': {
            'type': 'any',
            'items': [
              {
                'type': 'all',
                'items': [
                  {
                    'type': 'compare',
                    'left': {'field': 'value'},
                    'op': 'eq',
                    'right': {'value': 'x'},
                  },
                ],
              },
            ],
          },
        }, resolveField: (_) => 'x'),
        throwsA(isA<StateError>()),
      );
    });

    test('supports exists and empty operators', () {
      final exists = ConditionEvaluator.evaluate(const {
        'type': 'exists',
        'field': 'value',
      }, resolveField: (_) => '');
      final empty = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'field': 'value'},
        'op': 'is_empty',
      }, resolveField: (_) => '');

      expect(exists, isTrue);
      expect(empty, isTrue);
    });

    test('coerces scalar strings for equality and numeric comparisons', () {
      final numericComparison = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'value': '10'},
        'op': 'gt',
        'right': {'value': 2},
      }, resolveField: (_) => null);
      final numericEquality = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'value': 10},
        'op': 'eq',
        'right': {'value': '10'},
      }, resolveField: (_) => null);
      final booleanEquality = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'value': true},
        'op': 'eq',
        'right': {'value': 'true'},
      }, resolveField: (_) => null);
      final invalidComparison = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'value': 'not-a-number'},
        'op': 'gt',
        'right': {'value': 2},
      }, resolveField: (_) => null);

      expect(numericComparison, isTrue);
      expect(numericEquality, isTrue);
      expect(booleanEquality, isTrue);
      expect(invalidComparison, isFalse);
    });

    test('string and empty operators tolerate scalar values', () {
      for (final testCase in const [
        ('contains', '2'),
        ('starts_with', '12'),
        ('ends_with', '23'),
      ]) {
        final result = ConditionEvaluator.evaluate({
          'type': 'compare',
          'left': {'value': 123},
          'op': testCase.$1,
          'right': {'value': testCase.$2},
        }, resolveField: (_) => null);
        expect(result, isTrue, reason: testCase.$1);
      }

      final scalarIsEmpty = ConditionEvaluator.evaluate(const {
        'type': 'compare',
        'left': {'value': 123},
        'op': 'is_empty',
      }, resolveField: (_) => null);
      expect(scalarIsEmpty, isFalse);
    });

    test('propagates caller pending fields', () {
      expect(
        () => ConditionEvaluator.evaluate(const {
          'type': 'compare',
          'left': {'field': 'missing'},
          'op': 'eq',
          'right': {'value': true},
        }, resolveField: (field) => throw ConditionPending(field)),
        throwsA(
          isA<ConditionPending>().having(
            (error) => error.field,
            'field',
            'missing',
          ),
        ),
      );
    });
  });
}
