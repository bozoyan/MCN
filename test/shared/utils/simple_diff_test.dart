// 职责: 验证段落分段 diff 在整章散点改写下仍产出真实字符级高亮，而非退化成整块替换。
// 关联文件:
//   lib/shared/utils/simple_diff.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/simple_diff.dart';

/// 把 ops 里 delete/insert 的文本各自拼回，用于校验重建正确性。
String _reconstructSource(List<DiffOp> ops) =>
    ops.where((op) => op.kind != DiffOpKind.insert).map((op) => op.text).join();

String _reconstructResult(List<DiffOp> ops) =>
    ops.where((op) => op.kind != DiffOpKind.delete).map((op) => op.text).join();

void main() {
  group('computeSegmentedDiff', () {
    test('identical text yields a single equal op', () {
      final ops = computeSegmentedDiff('第一段\n第二段', '第一段\n第二段');
      expect(ops, hasLength(1));
      expect(ops.single.kind, DiffOpKind.equal);
    });

    test('unchanged paragraphs stay equal; only the edited one is refined', () {
      const source = '第一段没有改动。\n第二段这里被改写了。\n第三段也没有改动。';
      const result = '第一段没有改动。\n第二段那里被润色了。\n第三段也没有改动。';

      final ops = computeSegmentedDiff(source, result);

      // 未改动段落必须原样保留为 equal，其文本完整出现在 equal ops 中。
      final equalText = ops
          .where((op) => op.kind == DiffOpKind.equal)
          .map((op) => op.text)
          .join();
      expect(equalText, contains('第一段没有改动。'));
      expect(equalText, contains('第三段也没有改动。'));

      // 改动段落被细化到字符级：既有 delete 又有 insert，且不是把整篇一并替换。
      expect(ops.any((op) => op.kind == DiffOpKind.delete), isTrue);
      expect(ops.any((op) => op.kind == DiffOpKind.insert), isTrue);

      // 重建两侧文本必须与输入一致。
      expect(_reconstructSource(ops), source);
      expect(_reconstructResult(ops), result);
    });

    test(
      'scattered edits across a large chapter do not degrade to one giant block',
      () {
        // 构造一个远超字符级 diff 保护阈值（n*m > 2_000_000）的整章：
        // 每段独立改写。若没有段落分段，字符级 diff 会退化成单一 delete+insert。
        final srcParas = <String>[];
        final resParas = <String>[];
        for (var i = 0; i < 70; i++) {
          srcParas.add('第$i段：这是一段原始的中文正文内容，用于测试文本改写。');
          resParas.add('第$i段：这是一段被改写过的中文正文内容，用来测试改写效果。');
        }
        final source = srcParas.join('\n');
        final result = resParas.join('\n');
        expect(source.length * result.length, greaterThan(2000000));

        final ops = computeSegmentedDiff(source, result);

        // 关键回归断言：不能退化成「整段删除 + 整段插入」两个大块。
        final deletes = ops
            .where((op) => op.kind == DiffOpKind.delete)
            .toList();
        final wholeSourceDeleted =
            deletes.length == 1 && deletes.single.text == source;
        expect(wholeSourceDeleted, isFalse, reason: '整章应逐段细化，而非整篇一次性替换');

        // 未改动的重复片段（如「这是一段」「中文正文内容」）应作为 equal 保留。
        expect(ops.any((op) => op.kind == DiffOpKind.equal), isTrue);

        // 重建正确。
        expect(_reconstructSource(ops), source);
        expect(_reconstructResult(ops), result);
      },
    );

    test('streaming prefix leaves the un-reached tail as trailing deletes', () {
      const source = '第一段。\n第二段。\n第三段。';
      // 模拟流式：结果只到达前两段。
      const partial = '第一段。\n第二段。\n';

      final ops = computeSegmentedDiff(source, partial);

      // 尾部未到达的「第三段」应为末尾的 delete（供 UI 渲染成淡色待处理）。
      expect(ops.last.kind, DiffOpKind.delete);
      expect(ops.last.text, contains('第三段'));
      expect(_reconstructSource(ops), source);
      expect(_reconstructResult(ops), partial);
    });

    test(
      'mid-stream indentation does not drag un-reached paragraphs into the diff',
      () {
        // 原文：段首全角缩进 + 段间空行，1:1 改写场景。
        const source =
            '　　PARA一：食堂买了两个肉包。\n'
            '\n'
            '　　PARA二：外墙贴着白色瓷砖。\n'
            '\n'
            '　　PARA三：走廊尽头找到牌子。';
        // 流式：结果无缩进，仅揭示到第 2 段中间。
        const partial =
            'PARA一：食堂买了一个肉包。\n'
            '\n'
            'PARA二：外墙';

        final ops = computeSegmentedDiff(source, partial);

        // 尾部未到达内容折叠成一个 pending delete（UI 渲染成淡色）。
        var pendingFrom = ops.length;
        for (
          var i = ops.length - 1;
          i >= 0 && ops[i].kind == DiffOpKind.delete;
          i--
        ) {
          pendingFrom = i;
        }
        expect(
          pendingFrom,
          lessThan(ops.length),
          reason: '必须存在 pending 尾部 delete',
        );

        // 回归核心：第三段（未到达）绝不能因缩进导致的错位被卷进已上色的 diff 区，
        // 只能出现在末尾 pending delete 中。旧的 LCS 对齐会把它错配、字符级 diff 掉。
        for (var i = 0; i < pendingFrom; i++) {
          expect(
            ops[i].text.contains('PARA三'),
            isFalse,
            reason: '第三段不应出现在 pending 边界之前（说明发生了错位）',
          );
        }
        final pendingText = ops
            .sublist(pendingFrom)
            .map((op) => op.text)
            .join();
        expect(pendingText, contains('PARA三：走廊尽头找到牌子。'));

        // 已揭示段落对齐正确：两段的 "PARA" 前缀都应作为 equal 命中。
        final equalText = ops
            .where((op) => op.kind == DiffOpKind.equal)
            .map((op) => op.text)
            .join();
        expect(equalText, contains('PARA一'));
        expect(equalText, contains('PARA二'));

        expect(_reconstructSource(ops), source);
        expect(_reconstructResult(ops), partial);
      },
    );

    test(
      'stripped full-width indentation is an isolated whitespace-only delete',
      () {
        // 原文段首有全角缩进，改写结果去掉了缩进但正文一致。缩进应成为独立的、
        // 纯空白 delete op（供 UI 判定为空白、不高亮），正文其余部分保持 equal。
        const source = '　　凌晨两点半，林默盯着屏幕。';
        const result = '凌晨两点半，林默盯着屏幕。';

        final ops = computeSegmentedDiff(source, result);

        final whitespaceDeletes = ops.where(
          (op) => op.kind == DiffOpKind.delete && op.text.trim().isEmpty,
        );
        expect(whitespaceDeletes.map((op) => op.text).join(), '　　');
        // 不应把缩进和正文混进同一个内容级 delete，也不应产生任何 insert。
        expect(
          ops.any(
            (op) => op.kind == DiffOpKind.delete && op.text.trim().isNotEmpty,
          ),
          isFalse,
        );
        expect(ops.any((op) => op.kind == DiffOpKind.insert), isFalse);
        expect(_reconstructSource(ops), source);
        expect(_reconstructResult(ops), result);
      },
    );

    test(
      'extra blank line does not collapse later paragraphs into one block',
      () {
        // 复现：原文在两段之间多了一个空行（\n\n\n），改写结果是正常段间距。
        // 旧实现对到空行 vs 正文就放弃对齐，把后半章打成整块删除/插入。
        const source =
            '　　“2026 年是最后一次。”林默说。\n'
            '\n'
            '\n'
            '　　“为什么？”\n'
            '\n'
            '　　他把工控机放回墙里。\n'
            '\n'
            '　　而那个人，从来都不是他。';
        const result =
            '“2026年是最后一次了。”林默说。\n'
            '\n'
            '“为什么？”\n'
            '\n'
            '他将工控机放回墙里。\n'
            '\n'
            '而那个人，从来都不是他。';

        final ops = computeSegmentedDiff(source, result);

        final giantDeletes = ops.where(
          (op) =>
              op.kind == DiffOpKind.delete &&
              op.text.contains('为什么') &&
              op.text.contains('从来都不是他'),
        );
        expect(giantDeletes, isEmpty, reason: '多余空行后的段落应继续逐段对齐，不能整块替换');

        final equalText = ops
            .where((op) => op.kind == DiffOpKind.equal)
            .map((op) => op.text)
            .join();
        expect(equalText, contains('为什么'));
        expect(equalText, contains('从来都不是他'));

        expect(_reconstructSource(ops), source);
        expect(_reconstructResult(ops), result);
      },
    );

    test('extra blank line on the result side also keeps later pairing', () {
      const source =
          '第一段。\n'
          '\n'
          '第二段还在。';
      const result =
          '第一段改了。\n'
          '\n'
          '\n'
          '第二段还在。';

      final ops = computeSegmentedDiff(source, result);
      final equalText = ops
          .where((op) => op.kind == DiffOpKind.equal)
          .map((op) => op.text)
          .join();
      expect(equalText, contains('第二段还在。'));
      expect(_reconstructSource(ops), source);
      expect(_reconstructResult(ops), result);
    });
  });
}
