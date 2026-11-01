// 职责: 规整章节缩进、空行和中英文混排空白，同时保留英文词间分隔。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/services/chapter_format_all.dart

/// 段首缩进使用的单个全角空格（中文小说常用排版风格）。
const String _kFullWidthSpace = '\u3000';

final RegExp _cjkBeforeLatin = RegExp(
  r'([\u2E80-\u9FFF\uF900-\uFAFF])([A-Za-z0-9])',
);
final RegExp _latinBeforeCjk = RegExp(
  r'([A-Za-z0-9])([\u2E80-\u9FFF\uF900-\uFAFF])',
);
final RegExp _inlineWhitespace = RegExp(r'[\s\u3000]+');
final RegExp _cjkSpaceBoundary = RegExp(
  r'[\u2E80-\u9FFF\uF900-\uFAFF'
  r'\uFF01-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]',
);

/// 显式对中英文混排补半角空格（已有空格则跳过）。
///
/// 章节自动排版不调用此函数；仅供需要该间距风格时显式使用。
String applyCjkLatinSpacing(String text) {
  if (text.isEmpty) {
    return text;
  }
  var result = text;
  result = result.replaceAllMapped(
    _cjkBeforeLatin,
    (match) => '${match[1]} ${match[2]}',
  );
  result = result.replaceAllMapped(
    _latinBeforeCjk,
    (match) => '${match[1]} ${match[2]}',
  );
  return result;
}

/// 对小说章节正文进行自动排版。
///
/// 规则：
/// 1. 统一换行符为 `\n`；
/// 2. 去除每行首尾的空白（含半/全角空格、tab），空行视为分隔；
/// 3. 每个非空行视为一个段落，段首补齐 [indentCount] 个全角空格作为缩进；
/// 4. [allowSpaces] 为 true 时保留行内空白；为 false 时去除中文字符及全角
///    标点旁的空白，其余空白压成一个半角空格，避免英文单词或数字粘连；
/// 5. 段落之间按 [blankLineBetweenParagraphs] 决定是否插入一个空行。
///
/// 参数默认值对应「缩进 2 个全角空格、段落空一行、允许空格」，与设置默认值一致。
///
/// 设计：保持纯函数；不修改输入；可在按钮或粘贴回调中调用。
String formatText(
  String input, {
  int indentCount = 2,
  bool blankLineBetweenParagraphs = true,
  bool allowSpaces = true,
}) {
  if (input.isEmpty) {
    return input;
  }

  // 1. 统一换行符
  final unified = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final indent = _kFullWidthSpace * (indentCount < 0 ? 0 : indentCount);

  // 2. 按行处理：每个非空行作为一个段落。
  final paragraphs = <String>[];
  for (final raw in unified.split('\n')) {
    final normalized = _normalizeLine(
      raw,
      indent: indent,
      allowSpaces: allowSpaces,
    );
    if (normalized.isNotEmpty) {
      paragraphs.add(normalized);
    }
  }

  // 3. 段落之间按设置决定空行。
  final separator = blankLineBetweenParagraphs ? '\n\n' : '\n';
  return paragraphs.join(separator);
}

String _normalizeLine(
  String raw, {
  required String indent,
  required bool allowSpaces,
}) {
  // 同时去除半角空格、全角空格 \u3000、tab
  final stripped = raw.replaceAll(RegExp(r'^[\s\u3000]+|[\s\u3000]+$'), '');
  if (stripped.isEmpty) {
    return '';
  }
  if (!allowSpaces) {
    // 首尾空白已移除，剩余空白均有左右邻字。只清除中文边界的空白，
    // 英文（含标点）、数字及其他文字之间的分隔保留为一个半角空格。
    final normalized = stripped.replaceAllMapped(_inlineWhitespace, (match) {
      final touchesCjk =
          _cjkSpaceBoundary.matchAsPrefix(stripped, match.start - 1) != null ||
          _cjkSpaceBoundary.matchAsPrefix(stripped, match.end) != null;
      return touchesCjk ? '' : ' ';
    });
    return '$indent$normalized';
  }
  return '$indent$stripped';
}

/// 判断文本是否已经是“规范排版”后的结果（用于幂等判断、避免无意义写回）。
bool isChapterBodyFormatted(
  String input, {
  int indentCount = 2,
  bool blankLineBetweenParagraphs = true,
  bool allowSpaces = true,
}) {
  return formatText(
        input,
        indentCount: indentCount,
        blankLineBetweenParagraphs: blankLineBetweenParagraphs,
        allowSpaces: allowSpaces,
      ) ==
      input;
}
