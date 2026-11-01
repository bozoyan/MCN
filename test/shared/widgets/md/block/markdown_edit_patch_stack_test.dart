// 职责: 验证全文级撤销栈的可逆性与合并策略 — 连续输入合并成一步，撤销后光标回到编辑前位置
// 关联文件:
//   lib/shared/widgets/md/block/markdown_edit_patch_stack.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/code-style.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/md/block/markdown_edit_patch_stack.dart';

/// 可控时钟：合并窗口依赖时间，测试不能靠真实时钟。
class _FakeClock {
  DateTime _now = DateTime(2026, 8, 3);

  DateTime call() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

MarkdownEditPatch _insert(int start, String text, {int? before, int? after}) {
  return MarkdownEditPatch(
    start: start,
    removed: '',
    inserted: text,
    selectionBefore: before ?? start,
    selectionAfter: after ?? start + text.length,
  );
}

MarkdownEditPatch _delete(int start, String text, {int? before, int? after}) {
  return MarkdownEditPatch(
    start: start,
    removed: text,
    inserted: '',
    selectionBefore: before ?? start + text.length,
    selectionAfter: after ?? start,
  );
}

void main() {
  test('撤销恢复文本与编辑前光标，重做再次应用', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(2, '插入'));
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);

    final undone = stack.undo('原文插入内容');
    expect(undone, isNotNull);
    expect(undone!.text, '原文内容');
    expect(undone.selection, 2);
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isTrue);

    final redone = stack.redo('原文内容');
    expect(redone!.text, '原文插入内容');
    expect(redone.selection, 4);
  });

  test('合并窗口内的连续输入只算一步撤销', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    clock.advance(const Duration(milliseconds: 100));
    stack.record(_insert(1, '乙'));
    clock.advance(const Duration(milliseconds: 100));
    stack.record(_insert(2, '丙'));

    expect(stack.length, 1);
    final undone = stack.undo('甲乙丙尾');
    expect(undone!.text, '尾');
    expect(undone.selection, 0);
  });

  test('超出合并窗口后另起一步', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    clock.advance(const Duration(milliseconds: 900));
    stack.record(_insert(1, '乙'));

    expect(stack.length, 2);
    expect(stack.undo('甲乙')!.text, '甲');
    expect(stack.undo('甲')!.text, '');
  });

  test('换行不与前后输入合并', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    stack.record(_insert(1, '\n'));
    stack.record(_insert(2, '乙'));

    expect(stack.length, 3);
  });

  test('不连续的输入位置不合并', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    stack.record(_insert(9, '乙'));

    expect(stack.length, 2);
  });

  test('连续退格合并成一步', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    // 从「甲乙丙」末尾连按退格
    stack.record(_delete(2, '丙'));
    stack.record(_delete(1, '乙'));
    stack.record(_delete(0, '甲'));

    expect(stack.length, 1);
    final undone = stack.undo('');
    expect(undone!.text, '甲乙丙');
    expect(undone.selection, 3);
  });

  test('连续前向删除合并成一步', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_delete(0, '甲', before: 0, after: 0));
    stack.record(_delete(0, '乙', before: 0, after: 0));

    expect(stack.length, 1);
    expect(stack.undo('丙')!.text, '甲乙丙');
  });

  test('外部整篇写入不与前面的输入合并', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    stack.record(
      const MarkdownEditPatch(
        start: 0,
        removed: '甲',
        inserted: 'AI 生成的全文',
        selectionBefore: 1,
        selectionAfter: 8,
      ),
      mergeable: false,
    );

    expect(stack.length, 2);
    expect(stack.undo('AI 生成的全文')!.text, '甲');
  });

  test('记录新编辑会丢弃 redo 分支', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(0, '甲'));
    clock.advance(const Duration(seconds: 1));
    stack.record(_insert(1, '乙'));
    stack.undo('甲乙');
    expect(stack.canRedo, isTrue);

    clock.advance(const Duration(seconds: 1));
    stack.record(_insert(1, '丙'));
    expect(stack.canRedo, isFalse);
    expect(stack.length, 2);
  });

  test('超出历史上限时丢弃最旧的一步', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call, historyLimit: 3);

    for (var i = 0; i < 5; i++) {
      clock.advance(const Duration(seconds: 1));
      stack.record(_insert(i, '$i'));
    }

    expect(stack.length, 3);
    expect(stack.canUndo, isTrue);
    var text = '01234';
    var steps = 0;
    while (stack.canUndo) {
      text = stack.undo(text)!.text;
      steps++;
    }
    expect(steps, 3);
  });

  test('全文与栈不同步时放弃历史而不是产出错误文本', () {
    final clock = _FakeClock();
    final stack = MarkdownEditPatchStack(clock: clock.call);

    stack.record(_insert(10, '插入'));
    // 外部把正文换成了更短的内容，patch 的区间已经越界
    expect(stack.undo('短'), isNull);
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isFalse);
  });
}
