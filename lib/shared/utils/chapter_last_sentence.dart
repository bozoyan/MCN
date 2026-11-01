// 职责: 从章节正文中提取「上次写到」的最后一句预览文本 — 清洗 markdown、回溯非空行、剥离成对引号、截断并用中文引号包裹
// 关联文件:
//   lib/desktop/widgets/workspace/hero.dart
//   lib/mobile/widgets/overview_panel.dart

/// 从 [content] 中提取最后一句有内容的文本，作为「继续写作」的预览。
///
/// 返回值已用中文引号 “…” 包裹；超过 80 字会截断并加省略号。
/// 当正文为空或仅含空白/标点时返回 null。
String? _lastContent;
String? _lastResult;

String? extractLastWrittenSentence(String? content) {
  if (content == _lastContent) {
    return _lastResult;
  }

  final cleaned = _cleanContent(content);
  if (cleaned.isEmpty) {
    _lastContent = content;
    _lastResult = null;
    return null;
  }
  // 从最后一段非空行开始向前回溯，找到第一段含有实际字符的内容。
  // 这样可以跳过末尾仅有空白、章节分隔符或单独的标点行。
  final lines = cleaned
      .split(RegExp(r'\n+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return null;
  }
  for (int i = lines.length - 1; i >= 0; i--) {
    final sentence = _pickLastSentence(lines[i]);
    if (sentence == null) {
      continue;
    }
    // 句子可能自带成对的引号（中文对话常见 "…。"），
    // 外层 UI 还会再包一层引号，所以这里去掉两端的引号/括号避免重复。
    final stripped = _stripWrappingQuotes(sentence);
    if (stripped.isEmpty) {
      continue;
    }
    final trimmed = stripped.length > 80
        ? '${stripped.substring(0, 80)}…'
        : stripped;
    final result = '“$trimmed”';
    _lastContent = content;
    _lastResult = result;
    return result;
  }
  _lastContent = content;
  _lastResult = null;
  return null;
}

String _cleanContent(String? content) {
  if (content == null) {
    return '';
  }
  return content
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`>~]+'), '')
      .trim();
}

String _stripWrappingQuotes(String s) {
  return s
      .replaceAll(RegExp(r'^[“”"\u2018\u2019\u0027\(（【「『\[]+'), '')
      .replaceAll(RegExp(r'[“”"\u2018\u2019\u0027\)）】」』\]]+$'), '')
      .trim();
}

/// 在一行内按句末符号切分，返回最后一个含有实际字符的句子。
/// 会跳过结尾因为引号/括号/省略号等被切出的纯标点片段，
/// 例如 `这里藏着真正重要的东西。”` 切出的 `”` 不应被当作句子。
String? _pickLastSentence(String line) {
  final fragments = line
      .split(RegExp(r'(?<=[。！？!?…])'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (fragments.isEmpty) {
    return _hasMeaningfulChar(line) ? line : null;
  }
  for (int i = fragments.length - 1; i >= 0; i--) {
    if (_hasMeaningfulChar(fragments[i])) {
      return fragments[i];
    }
  }
  return null;
}

/// 判断字符串中是否含有 CJK / 字母 / 数字等「有内容」的字符；
/// 仅由引号、括号、省略号、标点组成的片段会被视为无意义。
bool _hasMeaningfulChar(String s) {
  return RegExp(
    r'[A-Za-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]',
  ).hasMatch(s);
}
