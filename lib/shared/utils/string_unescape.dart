// 职责: 将字符串中的字面量转义序列还原为实际字符，用于展示或存储外部接口或 AI 返回的含转义文本。
// 关联文件:

/// 将字符串中的字面量转义序列（如 `\n`、`\t`、`\r`、`\\`）还原为实际字符。
///
/// 用于处理模型或中间层把换行符以普通字符形式返回的情况，避免数据库和下游
/// 消费方拿到带转义的文本。
String unescapeDisplayString(String text) {
  if (text.isEmpty) {
    return text;
  }
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '\\' && i + 1 < text.length) {
      final next = text[i + 1];
      switch (next) {
        case 'n':
          buffer.write('\n');
          i++;
        case 't':
          buffer.write('\t');
          i++;
        case 'r':
          buffer.write('\r');
          i++;
        case '\\':
          buffer.write('\\');
          i++;
        default:
          buffer.write(char);
      }
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
