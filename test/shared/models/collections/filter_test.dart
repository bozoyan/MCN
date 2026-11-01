// 职责: 验证集合条件完整校验、复杂度边界与原文保留。
// 关联文件:
//   lib/shared/models/collections/filter.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/collections/filter.dart';

void main() {
  const compare = CollectionCompare('novel.title', 'contains', '科幻');
  test('accepts combinations and exact depth/node limits', () {
    expect(
      CollectionFilter.fromRoot(
        CollectionNot(CollectionGroup(false, [compare])),
      ).isValid,
      isTrue,
    );
    expect(
      () => CollectionFilter.fromRoot(
        const CollectionNot(CollectionNot(CollectionNot(compare))),
      ),
      throwsFormatException,
    );
    expect(
      CollectionFilter.fromRoot(
        CollectionGroup(false, List.filled(49, compare)),
      ).isValid,
      isTrue,
    );
    expect(
      () => CollectionFilter.fromRoot(
        CollectionGroup(false, List.filled(50, compare)),
      ),
      throwsFormatException,
    );
    expect(
      () => CollectionFilter.fromRoot(CollectionGroup(false, [])),
      throwsFormatException,
    );
  });
  test('never ignores unknown children or changes raw documents', () {
    final raw = jsonEncode({
      'version': 1,
      'root': CollectionGroup(true, [
        compare,
        const CollectionCompare('unknown', 'eq', 'x'),
      ]).toJson(),
    });
    final document = CollectionFilter.parse(raw);
    expect(document.status, CollectionFilterStatus.unsupported);
    expect(document.raw, raw);
    expect(document.reason, contains('items[1]'));
    expect(
      CollectionFilter.parse('{"version":2,"root":{}}').status,
      CollectionFilterStatus.unsupported,
    );
    expect(CollectionFilter.parse('not json').raw, 'not json');
  });
  test(
    'rejects coercion, extra keys, wrong empty operands; preserves whitespace',
    () {
      for (final value in [null, -1, 1.2, '12', true]) {
        expect(
          () => CollectionFilter.fromRoot(
            CollectionCompare('novel.word_count', 'eq', value),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => CollectionFilter.fromRoot(
          const CollectionCompare('novel.title', 'eq', ''),
        ),
        throwsFormatException,
      );
      expect(
        CollectionFilter.fromRoot(
          const CollectionCompare('novel.title', 'eq', ' '),
        ).isValid,
        isTrue,
      );
      final raw = jsonEncode({
        'version': 1,
        'root': {
          'type': 'compare',
          'left': {'field': 'novel.category'},
          'op': 'is_empty',
          'right': {'value': ''},
        },
      });
      expect(
        CollectionFilter.parse(raw).status,
        CollectionFilterStatus.damaged,
      );
      expect(
        CollectionFilter.parse('{"version":1,"root":{},"extra":1}').isValid,
        isFalse,
      );
    },
  );
}
