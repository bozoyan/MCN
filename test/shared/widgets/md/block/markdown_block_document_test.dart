// 职责: 验证分块文本模型的无损性 — 任意编辑序列后块区间仍连续覆盖全文，且偏移映射自洽
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_document.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/code-style.md
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/md/block/markdown_block_document.dart';

/// 块只是全文的区间视图，「拼回原文」等价于「区间连续覆盖全文」。
void expectLossless(MarkdownBlockDocument document) {
  expect(
    document.isContiguous,
    isTrue,
    reason: '块区间未连续覆盖全文: ${document.blocks}',
  );
  final buffer = StringBuffer();
  for (final block in document.blocks) {
    buffer.write(document.source.substring(block.start, block.separatorEnd));
  }
  expect(buffer.toString(), document.source);
}

void main() {
  group('切块', () {
    test('空文本恒有一个空块', () {
      final document = MarkdownBlockDocument.split('');
      expect(document.length, 1);
      expect(document[0].isEmpty, isTrue);
      expectLossless(document);
    });

    test('单个换行不切块，空行才切', () {
      final document = MarkdownBlockDocument.split('第一行\n第二行\n\n第二段');
      expect(document.length, 2);
      expect(document[0].textIn(document.source), '第一行\n第二行');
      expect(document[1].textIn(document.source), '第二段');
      expectLossless(document);
    });

    test('连续空行整体归入分隔区间', () {
      final document = MarkdownBlockDocument.split('甲\n\n\n\n乙');
      expect(document.length, 2);
      expect(document[0].textIn(document.source), '甲');
      expect(document[1].textIn(document.source), '乙');
      expectLossless(document);
    });

    test('分隔符不吃掉下一块的缩进', () {
      final document = MarkdownBlockDocument.split('段落\n\n  - 缩进列表项');
      expect(document[1].textIn(document.source), '  - 缩进列表项');
      expectLossless(document);
    });

    test('空行中的空格与制表符算作空行', () {
      final document = MarkdownBlockDocument.split('甲\n \t \n乙');
      expect(document.length, 2);
      expectLossless(document);
    });

    test('结尾空行产生一个可放光标的空尾块', () {
      final document = MarkdownBlockDocument.split('正文\n\n');
      expect(document.length, 2);
      expect(document.blocks.last.isEmpty, isTrue);
      expectLossless(document);
    });

    test('CRLF 不丢字符', () {
      final document = MarkdownBlockDocument.split('甲\r\n\r\n乙\r\n丙');
      expect(document.length, 2);
      expect(document[0].textIn(document.source), '甲');
      expectLossless(document);
    });

    test('全是空行时不丢内容', () {
      final document = MarkdownBlockDocument.split('\n\n\n\n');
      expectLossless(document);
    });
  });

  group('偏移映射', () {
    final document = MarkdownBlockDocument.split('甲甲\n\n乙乙乙\n\n丙');

    test('locate 与 offsetOf 互逆', () {
      for (var offset = 0; offset <= document.source.length; offset++) {
        final located = document.locate(offset);
        final back = document.offsetOf(located.block, located.local);
        final block = document[located.block];
        // 分隔符区间内的偏移会被夹到所在块末尾，其余位置必须精确往返。
        if (offset >= block.start && offset <= block.end) {
          expect(back, offset, reason: 'offset=$offset');
        } else {
          expect(back, block.end, reason: 'offset=$offset 落在分隔符区间');
        }
      }
    });

    test('块索引单调且覆盖全部偏移', () {
      var previous = 0;
      for (var offset = 0; offset <= document.source.length; offset++) {
        final index = document.blockIndexAt(offset);
        expect(index, greaterThanOrEqualTo(previous));
        previous = index;
      }
    });
  });

  group('增量编辑', () {
    test('块内输入不改变块结构，只有被编辑的块换 id', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙\n\n丙\n\n丁\n\n戊');
      final ids = before.blocks.map((block) => block.id).toList();
      final after = before.replaceBlock(2, '丙丙');

      expect(after.source, '甲\n\n乙\n\n丙丙\n\n丁\n\n戊');
      expect(after.length, before.length);
      expect(after.blocks.map((block) => block.id).toList(), [
        ids[0],
        ids[1],
        isNot(ids[2]),
        ids[3],
        ids[4],
      ]);
      expectLossless(after);
    });

    test('块内插入空行导致分裂', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙丙\n\n丁');
      final after = before.replaceBlock(1, '乙\n\n丙');

      expect(after.source, '甲\n\n乙\n\n丙\n\n丁');
      expect(after.length, 4);
      expect(after[1].textIn(after.source), '乙');
      expect(after[2].textIn(after.source), '丙');
      expectLossless(after);
    });

    test('删除分隔符导致相邻块合并', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙\n\n丙');
      // 删掉「甲」和「乙」之间的空行
      final after = before.replaceRange(1, 3, '');

      expect(after.source, '甲乙\n\n丙');
      expect(after.length, 2);
      expect(after[0].textIn(after.source), '甲乙');
      expectLossless(after);
    });

    test('跨多块删除', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙\n\n丙\n\n丁');
      final after = before.replaceRange(1, before.source.length - 1, '');

      expect(after.source, '甲丁');
      expect(after.length, 1);
      expectLossless(after);
    });

    test('未受影响的块保留原 id', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙\n\n丙\n\n丁\n\n戊');
      final firstId = before.blocks.first.id;
      final lastId = before.blocks.last.id;
      final after = before.replaceBlock(2, '丙\n\n丙二');

      expect(after.blocks.first.id, firstId);
      expect(after.blocks.last.id, lastId);
      expectLossless(after);
    });

    test('resplit 后仍无损', () {
      final before = MarkdownBlockDocument.split('甲\n\n乙');
      final after = before.resplit('完全不同的\n\n新正文\n\n三段');

      expect(after.length, 3);
      expectLossless(after);
    });
  });

  test('随机编辑序列后始终无损（property）', () {
    final random = Random(20260803);
    const alphabet = '甲乙丙丁戊abc \t';
    var document = MarkdownBlockDocument.split('起始段落\n\n第二段\n\n第三段');
    var shadow = document.source;

    for (var step = 0; step < 600; step++) {
      final length = shadow.length;
      final start = length == 0 ? 0 : random.nextInt(length + 1);
      final end = start + random.nextInt(max(1, min(12, length - start + 1)));
      final safeEnd = end.clamp(start, length);

      final buffer = StringBuffer();
      final insertLength = random.nextInt(6);
      for (var i = 0; i < insertLength; i++) {
        final roll = random.nextInt(10);
        if (roll == 0) {
          buffer.write('\n');
        } else if (roll == 1) {
          buffer.write('\n\n');
        } else if (roll == 2) {
          buffer.write('\r\n');
        } else {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
      }
      final replacement = buffer.toString();

      document = document.replaceRange(start, safeEnd, replacement);
      shadow = shadow.replaceRange(start, safeEnd, replacement);

      expect(document.source, shadow, reason: 'step=$step');
      expectLossless(document);
    }
  });

  test('局部编辑不重切全文（复杂度）', () {
    final source = List.generate(3000, (i) => '第 $i 段正文内容').join('\n\n');
    var document = MarkdownBlockDocument.split(source);
    expect(document.length, 3000);

    // 反复编辑中间一块，块总数与两端 id 都不应变化。
    final firstId = document.blocks.first.id;
    final lastId = document.blocks.last.id;
    for (var i = 0; i < 200; i++) {
      document = document.replaceBlock(1500, '第 1500 段正文内容$i');
    }

    expect(document.length, 3000);
    expect(document.blocks.first.id, firstId);
    expect(document.blocks.last.id, lastId);
    expectLossless(document);
  });
}
