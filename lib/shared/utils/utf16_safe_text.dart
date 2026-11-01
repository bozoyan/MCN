// 职责: 提供 UTF-16 代理对安全的截断与切片判断，避免展示文本出现落单代理导致渲染抛错。
// 关联文件:
//   lib/desktop/features/council/replay_controller.dart
//   lib/shared/models/chapter.dart
//   lib/shared/models/character_profile.dart

/// 判断 [index] 是否落在 [text] 某个代理对（如 emoji）的两个 code unit 中间。
///
/// `index` 需在 `(0, text.length)` 区间内才可能为 true。
bool splitsSurrogatePair(String text, int index) {
  if (index <= 0 || index >= text.length) {
    return false;
  }
  final prev = text.codeUnitAt(index - 1);
  final next = text.codeUnitAt(index);
  final prevIsHigh = prev >= 0xD800 && prev <= 0xDBFF;
  final nextIsLow = next >= 0xDC00 && next <= 0xDFFF;
  return prevIsHigh && nextIsLow;
}

/// 截断到最多 [maxLength] 个 code unit，边界落在代理对中间时回退一位，
/// 保证返回值是合法 UTF-16，可安全交给 TextSpan / ParagraphBuilder 渲染。
String truncateUtf16Safe(
  String text,
  int maxLength, {
  String ellipsis = '...',
}) {
  if (text.length <= maxLength) {
    return text;
  }
  var end = maxLength;
  if (splitsSurrogatePair(text, end)) {
    end -= 1;
  }
  return text.substring(0, end) + ellipsis;
}
