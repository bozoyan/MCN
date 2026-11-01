// 职责: 共享文本清洗工具 — 处理无效 UTF-16 surrogate pair，避免上游 API 编码报错
// 关联文件:
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/openai_responses_client.dart
//   lib/shared/agent/client/gemini_client.dart

String sanitizeSurrogates(String input) {
  if (input.isEmpty) return input;
  final units = input.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final cu = units[i];
    if (cu >= 0xD800 && cu <= 0xDBFF) {
      if (i + 1 < units.length) {
        final next = units[i + 1];
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.writeCharCode(cu);
          out.writeCharCode(next);
          i++;
          continue;
        }
      }
      out.writeCharCode(0xFFFD);
      continue;
    }
    if (cu >= 0xDC00 && cu <= 0xDFFF) {
      out.writeCharCode(0xFFFD);
      continue;
    }
    out.writeCharCode(cu);
  }
  return out.toString();
}
