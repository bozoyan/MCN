// 职责: 验证按行接受合成与双栏对齐 — 无退回、全退、混合、成对修改行、新建、无效键边界、审阅行配对与退回判定、退回行数统计。
// 关联文件:
//   lib/shared/utils/line_accept.dart
//   lib/shared/utils/line_diff.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/line_accept.dart';
import 'package:reveric/shared/utils/line_diff.dart';

void main() {
  // old: [a, b, c, d] → new: [a, B, c, e]
  // diff: context a | -b(d:2) +B(i:2) | context c | -d(d:4) +e(i:4)
  const oldText = 'a\nb\nc\nd';
  const newText = 'a\nB\nc\ne';

  group('computeLineAcceptResult', () {
    test('无退回时结果等于 newText', () {
      expect(computeLineAcceptResult(oldText, newText, const {}), newText);
    });

    test('全部变更行被退回时结果等于 oldText', () {
      final result = computeLineAcceptResult(oldText, newText, {
        'd:2',
        'i:2',
        'd:4',
        'i:4',
      });
      expect(result, oldText);
    });

    test('混合退回只保留被接受的行', () {
      // 退回 b 的删除（b 保留）+ 退回 e 的新增（e 丢弃）；
      // d 的删除未被退回（d 丢弃）+ B 的新增未被退回（B 保留）。
      // 保留顺序按 diff 块位置：b/B 块在 context c 之前。
      final result = computeLineAcceptResult(oldText, newText, {'d:2', 'i:4'});
      expect(result, 'a\nb\nB\nc');
    });

    test('成对修改行相互独立：退回删除但保留新增会同时保留两行', () {
      final result = computeLineAcceptResult(oldText, newText, {'d:2'});
      expect(result, 'a\nb\nB\nc\ne');
    });

    test('新建（old 为空）全部退回后为空', () {
      final result = computeLineAcceptResult(null, 'x\ny', {'i:1', 'i:2'});
      expect(result, '');
    });

    test('新建（old 为空）无退回时保留全部新行', () {
      expect(computeLineAcceptResult('', 'x\ny', const {}), 'x\ny');
    });

    test('不存在的行键被忽略，结果等于 newText', () {
      expect(
        computeLineAcceptResult(oldText, newText, {'d:99', 'x:1'}),
        newText,
      );
    });

    test('两端都为空时返回空串', () {
      expect(computeLineAcceptResult(null, null, const {'i:1'}), '');
    });

    test('退回行键不影响 context 行', () {
      // context 行没有行键；传入 context 行号构造的键不应改变结果。
      final result = computeLineAcceptResult(oldText, newText, {'d:1', 'i:1'});
      expect(result, newText);
    });
  });

  group('lineAcceptKeyFor', () {
    test('delete/insert 行生成稳定键，context 行为空串', () {
      final entries = computeLineDiff(oldText, newText);
      final keys = entries.map(lineAcceptKeyFor).toList();
      expect(keys, ['', 'd:2', 'i:2', '', 'd:4', 'i:4']);
    });
  });

  group('lineReviewLayoutFor', () {
    test('删增混合为 mixed', () {
      expect(lineReviewLayoutFor(oldText, newText), LineReviewLayout.mixed);
    });

    test('纯新增为 pure_insert', () {
      expect(lineReviewLayoutFor(null, 'x\ny'), LineReviewLayout.pure_insert);
      expect(lineReviewLayoutFor('', 'x'), LineReviewLayout.pure_insert);
    });

    test('纯删除为 pure_delete', () {
      expect(lineReviewLayoutFor('x\ny', ''), LineReviewLayout.pure_delete);
    });

    test('无变更或两端为空为 none', () {
      expect(lineReviewLayoutFor(oldText, oldText), LineReviewLayout.none);
      expect(lineReviewLayoutFor(null, null), LineReviewLayout.none);
    });
  });

  group('alignLineReviewRows', () {
    test('context 行左右同文，修改行左右配对', () {
      // old: [a, b, c] → new: [a, B, c]
      final rows = alignLineReviewRows(computeLineDiff('a\nb\nc', 'a\nB\nc'));
      expect(rows.length, 3);
      expect(rows[0].isContext, isTrue);
      expect(rows[0].left, same(rows[0].right));
      expect(rows[1].isContext, isFalse);
      expect(rows[1].left?.text, 'b');
      expect(rows[1].right?.text, 'B');
      expect(rows[1].lineKeys, ['d:2', 'i:2']);
      expect(rows[2].isContext, isTrue);
    });

    test('删除多于新增时，多余删除行右侧留空', () {
      // old: [a, x, y, b] → new: [a, z, b]
      final rows = alignLineReviewRows(
        computeLineDiff('a\nx\ny\nb', 'a\nz\nb'),
      );
      expect(rows.length, 4);
      expect(rows[1].left?.text, 'x');
      expect(rows[1].right?.text, 'z');
      expect(rows[2].left?.text, 'y');
      expect(rows[2].right, isNull);
      expect(rows[2].lineKeys, ['d:3']);
    });

    test('新增多于删除时，多余新增行左侧留空', () {
      // old: [a, x, b] → new: [a, y, z, b]
      final rows = alignLineReviewRows(
        computeLineDiff('a\nx\nb', 'a\ny\nz\nb'),
      );
      expect(rows.length, 4);
      expect(rows[1].left?.text, 'x');
      expect(rows[1].right?.text, 'y');
      expect(rows[2].left, isNull);
      expect(rows[2].right?.text, 'z');
      expect(rows[2].lineKeys, ['i:3']);
    });

    test('纯新增时全部为右侧单列行', () {
      final rows = alignLineReviewRows(computeLineDiff('', 'x\ny'));
      expect(rows.length, 2);
      expect(rows.every((row) => row.left == null), isTrue);
      expect(rows.map((row) => row.lineKeys), [
        ['i:1'],
        ['i:2'],
      ]);
    });
  });

  group('isLineReviewRowReverted', () {
    test('行内全部行键被退回才算退回', () {
      final rows = alignLineReviewRows(computeLineDiff('a\nb\nc', 'a\nB\nc'));
      final modifyRow = rows[1];
      expect(isLineReviewRowReverted(modifyRow, {'d:2', 'i:2'}), isTrue);
      expect(isLineReviewRowReverted(modifyRow, {'d:2'}), isFalse);
      expect(isLineReviewRowReverted(modifyRow, const {}), isFalse);
    });

    test('context 行始终视为未退回', () {
      final rows = alignLineReviewRows(computeLineDiff('a\nb\nc', 'a\nB\nc'));
      expect(isLineReviewRowReverted(rows[0], {'d:1', 'i:1'}), isFalse);
    });

    test('纯新增行只看新增键', () {
      final rows = alignLineReviewRows(computeLineDiff('', 'x\ny'));
      expect(isLineReviewRowReverted(rows[0], {'i:1'}), isTrue);
      expect(isLineReviewRowReverted(rows[1], {'i:1'}), isFalse);
    });
  });

  group('countRejectedReviewRows', () {
    test('配对的修改行（删除+新增键）算 1 行', () {
      // old: [a, b, c] → new: [a, B, c]；d:2 与 i:2 是同一审阅行
      expect(countRejectedReviewRows('a\nb\nc', 'a\nB\nc', {'d:2', 'i:2'}), 1);
    });

    test('修改行与纯删除行各算 1 行', () {
      // old: [a, x, y, b] → new: [a, z, b]：修改行(x→z) + 纯删除行(y)
      expect(
        countRejectedReviewRows('a\nx\ny\nb', 'a\nz\nb', {'d:2', 'i:2', 'd:3'}),
        2,
      );
    });

    test('行内行键未全部退回时不计入', () {
      expect(countRejectedReviewRows('a\nb\nc', 'a\nB\nc', {'d:2'}), 0);
    });

    test('空集合或无变更时为 0', () {
      expect(countRejectedReviewRows('a\nb\nc', 'a\nB\nc', const {}), 0);
      expect(countRejectedReviewRows('a', 'a', {'d:1'}), 0);
      expect(countRejectedReviewRows(null, null, {'i:1'}), 0);
    });
  });
}
