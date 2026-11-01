// 职责: 验证整场撤销、保存回流、跨元素替换、角色保护与输入法事务。
// 关联文件:
//   lib/shared/widgets/screenplay/editing_controller.dart
//   lib/shared/models/screenplay_editing.dart
//   lib/shared/models/screenplay_element.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/screenplay_editing.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/widgets/screenplay/editing_controller.dart';

void main() {
  ScreenplayEditingController create(List<ScreenplayElement> elements) {
    final controller = ScreenplayEditingController(
      elements,
      ScreenplayElementKeys(),
    );
    controller.onEdited = (_) {};
    controller.confirmDelete = () async => false;
    addTearDown(controller.dispose);
    return controller;
  }

  const first = ScreenplayElement(
    id: 'first',
    type: ScreenplayElementType.action,
    text: 'alpha',
  );
  const second = ScreenplayElement(
    id: 'second',
    type: ScreenplayElementType.action,
    text: 'beta',
  );

  test('保存回流保留整场撤销，重做复用首次保存分配的 ID', () async {
    final editor = create([first]);
    final added = ScreenplayElement(
      type: ScreenplayElementType.action,
      text: 'new',
    );
    editor.edit([first, added]);
    await Future<void>.delayed(Duration.zero);
    final saved = [first, added.copyWith(id: 'new-id')];
    editor.acceptSave([first, added], saved);
    editor.acceptExternal(saved);
    editor.undo();
    expect(editor.value.map((e) => e.text), ['alpha']);
    editor.redo();
    expect(editor.value.last.id, 'new-id');
    expect(editor.value.last.text, 'new');
  });

  test('跨元素选区替换与撤销同时恢复内容和选区', () async {
    final editor = create([first, second]);
    const selection = TextSelection(baseOffset: 2, extentOffset: 8);
    editor.select(selection);
    expect(editor.selectedText(), 'pha\nbe');
    await editor.replaceSelection('X');
    expect(editor.value.map((e) => e.text), ['alXta']);
    expect(editor.selection.extentOffset, 3);
    editor.undo();
    expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
    expect(editor.selection, selection);
    editor.redo();
    expect(editor.value.single.text, 'alXta');
  });

  test('查找全部替换保留软换行、角色引用和各元素类型', () async {
    final editor = create([
      first.copyWith(text: 'foo\nfoo'),
      const ScreenplayElement(
        id: 'speaker',
        type: ScreenplayElementType.character,
        characterId: 'person',
      ),
      const ScreenplayElement(
        id: 'speech',
        type: ScreenplayElementType.dialogue,
        text: 'foo',
      ),
    ]);
    editor.document.text = editor.source.replaceAll('foo', 'bar');
    expect(editor.value.map((e) => e.text), ['bar\nbar', '', 'bar']);
    expect(editor.value[1].characterId, 'person');
    expect(editor.value.last.type, ScreenplayElementType.dialogue);
    editor.undo();
    expect(editor.value.first.text, 'foo\nfoo');
    expect(editor.value.last.text, 'foo');
  });

  test('剪切角色但未选中后续对白时先确认整块删除', () async {
    final editor = create([
      const ScreenplayElement(
        id: 'speaker',
        type: ScreenplayElementType.character,
        characterId: 'person',
      ),
      const ScreenplayElement(
        id: 'speech',
        type: ScreenplayElementType.dialogue,
        text: 'keep',
      ),
      second,
    ]);
    editor.characterNames = {'person': 'Speaker'};
    editor.select(const TextSelection(baseOffset: 0, extentOffset: 1));
    expect(editor.selectedText(), 'Speaker：');
    await editor.replaceSelection('');
    expect(editor.value.length, 3);
    editor.confirmDelete = () async => true;
    String? clipboard;
    await editor.replaceRange(
      editor.selection.start,
      editor.selection.end,
      '',
      beforeReplace: (text) async {
        clipboard = text;
      },
    );
    expect(clipboard, 'Speaker：\nkeep');
    expect(editor.value.map((e) => e.text), ['beta']);
    editor.undo();
    expect(editor.value.map((e) => e.type), [
      ScreenplayElementType.character,
      ScreenplayElementType.dialogue,
      ScreenplayElementType.action,
    ]);
  });

  test('全选删除后可以直接粘贴，撤销恢复整场', () async {
    final editor = create([first, second]);
    editor.select(
      TextSelection(baseOffset: 0, extentOffset: editor.source.length),
    );
    await editor.replaceSelection('');
    await Future<void>.delayed(Duration.zero);
    expect(editor.value, isEmpty);
    await editor.replaceSelection('new\nbody');
    expect(editor.value.single.text, 'new\nbody');
    editor.undo();
    expect(editor.value, isEmpty);
    editor.undo();
    expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
  });

  test('IME 组词期间不保存，提交后可一次撤销', () async {
    final editor = create([first.copyWith(text: '')]);
    var saves = 0;
    editor.onEdited = (_) => saves++;
    const preedit = TextEditingValue(
      text: '中',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );
    editor.observeInput(
      0,
      preedit,
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    editor.edit([editor.value.first.copyWith(text: '中')]);
    await Future<void>.delayed(Duration.zero);
    expect(saves, 0);
    editor.observeInput(
      0,
      preedit.copyWith(composing: TextRange.empty),
      preedit,
    );
    await Future<void>.delayed(Duration.zero);
    expect(saves, 1);
    editor.undo();
    expect(editor.value.single.text, '');
  });

  test('跨元素键入 emoji 不会只取 UTF-16 的半个字符', () async {
    final editor = create([first, second.copyWith(text: '😁')]);
    editor.select(
      TextSelection(baseOffset: 0, extentOffset: editor.source.length),
    );
    editor.observeInput(
      1,
      const TextEditingValue(
        text: '😀',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: '😁',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      ),
    );
    editor.edit([first, second.copyWith(text: '😀')]);
    await Future<void>.delayed(Duration.zero);
    expect(editor.value.single.text, '😀');
    editor.undo();
    expect(editor.value.last.text, '😁');
  });

  test('跨元素 Enter 是一个可撤销的拆行操作，Shift+Enter 保留元素', () async {
    final editor = create([first, second]);
    editor.select(const TextSelection(baseOffset: 2, extentOffset: 8));
    await editor.enter(soft: false);
    expect(editor.value.map((e) => e.text), ['al', 'ta']);
    editor.undo();
    expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
    editor.select(const TextSelection.collapsed(offset: 2));
    await editor.enter(soft: true);
    expect(editor.value.map((e) => e.text), ['al\npha', 'beta']);
    editor.undo();
    expect(editor.value.first.text, 'alpha');
  });

  test('选区结束在角色之前不会删除未选中的角色和对白', () async {
    final editor = create([
      first,
      const ScreenplayElement(
        id: 'role',
        type: ScreenplayElementType.character,
        characterId: 'person',
      ),
      const ScreenplayElement(
        id: 'speech',
        type: ScreenplayElementType.dialogue,
        text: 'keep',
      ),
    ]);
    editor.select(
      TextSelection(baseOffset: 0, extentOffset: editor.startOf(1)),
    );
    await editor.replaceSelection('');
    expect(editor.value.map((e) => e.type), [
      ScreenplayElementType.character,
      ScreenplayElementType.dialogue,
    ]);
    expect(editor.value.last.text, 'keep');
  });

  test('在选中的角色行粘贴会接续对白，保留人物引用', () async {
    final editor = create([
      const ScreenplayElement(
        id: 'role',
        type: ScreenplayElementType.character,
        characterId: 'person',
      ),
      second,
    ]);
    editor.select(const TextSelection.collapsed(offset: 1));
    await editor.replaceSelection('hello');
    expect(editor.value.map((e) => e.type), [
      ScreenplayElementType.character,
      ScreenplayElementType.dialogue,
      ScreenplayElementType.action,
    ]);
    expect(editor.value[1].text, 'hello');
    expect(editor.value.first.characterId, 'person');
  });
}
