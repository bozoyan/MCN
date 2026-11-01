// 职责: 统一剧本元素的编辑身份、文字拆分、插入、类型转换与角色上下文约束。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/desktop/features/screenplay/script.dart
//   lib/mobile/features/screenplay/scene_editor.dart

import 'screenplay_element.dart';

/// 编辑行的身份独立于落库 ID；首次保存回流时仍复用原输入框。
/// 新行须使用独立的元素实例，文本和类型更新通过 preserveKey 延续身份。
class ScreenplayElementKeys {
  final _draftKeys = Expando<Object>();
  final _savedKeys = <String, Object>{};

  Object keyFor(ScreenplayElement element) {
    final id = element.id;
    if (id != null) {
      return _savedKeys[id] ?? id;
    }
    return _draftKeys[element] ??= Object();
  }

  ScreenplayElement preserveKey(
    ScreenplayElement previous,
    ScreenplayElement next,
  ) {
    if (next.id == null) {
      _draftKeys[next] = keyFor(previous);
    }
    return next;
  }

  /// writeElements 按提交顺序返回元素，用保存前的行身份关联新分配的 ID。
  void acceptSave(
    List<ScreenplayElement> snapshot,
    List<ScreenplayElement> saved,
  ) {
    for (var index = 0; index < saved.length; index++) {
      _savedKeys[saved[index].id!] = keyFor(snapshot[index]);
    }
  }
}

ScreenplayElementType screenplayNextElementType(ScreenplayElementType type) =>
    switch (type) {
      ScreenplayElementType.character ||
      ScreenplayElementType.parenthetical => ScreenplayElementType.dialogue,
      _ => ScreenplayElementType.action,
    };

({String before, String after}) splitScreenplayText(
  String text,
  int selectionStart,
  int selectionEnd,
) {
  final start = selectionStart < 0 ? text.length : selectionStart;
  final end = selectionEnd < 0 ? text.length : selectionEnd;
  return (before: text.substring(0, start), after: text.substring(end));
}

/// 仅把一次输入的换行视为 Enter；粘贴多行文字仍保留在原元素中。
/// 光标偏移用于区分连续换行和已有换行；输入法组词由调用方拦截。
({String before, String after})? screenplayInsertedNewline(
  String previous,
  String text,
  int cursor,
) {
  if (cursor <= 0 || cursor > text.length || text[cursor - 1] != '\n') {
    return null;
  }
  final before = text.substring(0, cursor - 1);
  final after = text.substring(cursor);
  if (!previous.startsWith(before) ||
      !previous.endsWith(after) ||
      before.length + after.length > previous.length) {
    return null;
  }
  return (before: before, after: after);
}

ScreenplayElement changeScreenplayElementType(
  ScreenplayElement element,
  ScreenplayElementType type, {
  String? characterId,
}) => ScreenplayElement(
  id: element.id,
  episodeId: element.episodeId,
  sceneId: element.sceneId,
  type: type,
  text: type == ScreenplayElementType.character ? '' : element.text,
  characterId: type == ScreenplayElementType.character
      ? characterId ?? element.characterId
      : null,
  extension: type == ScreenplayElementType.character ? element.extension : '',
);

bool canChangeScreenplayElementType(
  List<ScreenplayElement> elements,
  int index,
  ScreenplayElementType type,
) {
  if (type == ScreenplayElementType.scene_heading ||
      (index >= 0 && index < elements.length && elements[index].isHeading) ||
      index < 0 ||
      index > elements.length) {
    return false;
  }
  var hasCharacter = false;
  for (
    var i = 0;
    i < elements.length + (index == elements.length ? 1 : 0);
    i++
  ) {
    final current = i == index ? type : elements[i].type;
    if (current == ScreenplayElementType.character) {
      hasCharacter = true;
    } else if (current == ScreenplayElementType.dialogue ||
        current == ScreenplayElementType.parenthetical) {
      if (!hasCharacter) {
        return false;
      }
    } else {
      hasCharacter = false;
    }
  }
  return true;
}

List<ScreenplayElement> insertScreenplayElement(
  List<ScreenplayElement> elements,
  int index,
  ScreenplayElement element,
) => [...elements]..insert(index, element);

/// 选人后接着写对白：复用该角色块的首条对白，缺少时在括号提示之后补一行。
({List<ScreenplayElement> elements, int index}) prepareScreenplayDialogue(
  List<ScreenplayElement> elements,
  int characterIndex,
) {
  assert(elements[characterIndex].type == ScreenplayElementType.character);
  var index = characterIndex + 1;
  while (index < elements.length &&
      elements[index].type == ScreenplayElementType.parenthetical) {
    index++;
  }
  if (index < elements.length &&
      elements[index].type == ScreenplayElementType.dialogue) {
    return (elements: elements, index: index);
  }
  return (
    elements: insertScreenplayElement(
      elements,
      index,
      ScreenplayElement(type: ScreenplayElementType.dialogue),
    ),
    index: index,
  );
}
