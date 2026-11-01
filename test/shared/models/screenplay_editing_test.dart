// 职责: 验证两端共享的剧本换行、插入及角色上下文编辑规则。
// 关联文件:
//   lib/shared/models/screenplay_editing.dart
//   lib/shared/models/screenplay_element.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/screenplay_editing.dart';
import 'package:reveric/shared/models/screenplay_element.dart';

void main() {
  test('splits at the caret and replaces a selected range', () {
    expect(splitScreenplayText('前文后文', 2, 2), (before: '前文', after: '后文'));
    expect(splitScreenplayText('前文选中后文', 2, 4), (before: '前文', after: '后文'));
    expect(splitScreenplayText('末尾', 2, 2), (before: '末尾', after: ''));
  });

  test('recognizes soft keyboard enter without splitting pasted text', () {
    expect(screenplayInsertedNewline('前文后文', '前文\n后文', 3), (
      before: '前文',
      after: '后文',
    ));
    expect(screenplayInsertedNewline('前文选中后文', '前文\n后文', 3), (
      before: '前文',
      after: '后文',
    ));
    expect(screenplayInsertedNewline('', '粘贴\n多行', 5), isNull);
    expect(screenplayInsertedNewline('原文', '原文\n', 3), (
      before: '原文',
      after: '',
    ));
  });

  test('insert preserves existing IDs and leaves new IDs to persistence', () {
    const original = [
      ScreenplayElement(
        id: 'old',
        type: ScreenplayElementType.action,
        text: '原文',
      ),
    ];
    final next = insertScreenplayElement(
      original,
      1,
      const ScreenplayElement(type: ScreenplayElementType.action, text: '新行'),
    );
    expect(original.length, 1);
    expect(next.first.id, 'old');
    expect(next.last.id, isNull);
    final third = insertScreenplayElement(
      next,
      1,
      const ScreenplayElement(type: ScreenplayElementType.action),
    );
    expect(third.last.id, next.last.id);
    expect(third[1].id, isNull);
    expect(third.last.text, '新行');
  });

  test('type changes cannot orphan following dialogue', () {
    const elements = [
      ScreenplayElement(
        type: ScreenplayElementType.character,
        characterId: 'person',
      ),
      ScreenplayElement(type: ScreenplayElementType.dialogue, text: '你好'),
    ];
    expect(
      canChangeScreenplayElementType(elements, 0, ScreenplayElementType.action),
      isFalse,
    );
    expect(
      canChangeScreenplayElementType(
        elements,
        1,
        ScreenplayElementType.parenthetical,
      ),
      isTrue,
    );
    expect(
      canChangeScreenplayElementType([], 0, ScreenplayElementType.dialogue),
      isFalse,
    );
    final changed = changeScreenplayElementType(
      elements.first,
      ScreenplayElementType.action,
    );
    expect(changed.characterId, isNull);
    expect(changed.extension, isEmpty);
  });

  test('continuation types match screenplay rules on both platforms', () {
    expect(
      screenplayNextElementType(ScreenplayElementType.character),
      ScreenplayElementType.dialogue,
    );
    expect(
      screenplayNextElementType(ScreenplayElementType.parenthetical),
      ScreenplayElementType.dialogue,
    );
    expect(
      screenplayNextElementType(ScreenplayElementType.dialogue),
      ScreenplayElementType.action,
    );
  });
}
