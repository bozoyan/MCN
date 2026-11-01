// 职责: AI 结构化提示 XML 工具 — 转义 XML attribute 与文本节点值。
// 关联文件:
//   lib/shared/services/ai/chat_prompt_builder.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/desktop/widgets/ai/chat/runtime.dart

String escapeXmlAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll("'", '&apos;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String escapeXmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
