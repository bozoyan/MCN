// 职责: Agent token 估算器 — 遍历 content + 全部 blocks 估算 token，CJK 计权偏高估；UTF-16 代理对安全截断
// 关联文件:
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/agent/message.dart
//   lib/shared/services/ai/context_manager.dart

import 'dart:convert';

import 'message.dart';

/// 估算一段文本的 token 数。
///
/// CJK 字符按 1 token 计（偏高估，实际 ≈ 1–1.5 字符/token），
/// 非 CJK 字符按 ÷4 计（偏高估，实际 ≈ 4 字符/token）。
/// 刻意偏高估以触发压缩更早（宁可早压缩不可晚报错）。
int estimateTextTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var other = 0;
  for (final char in text.runes) {
    if (_isCjk(char)) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + (other ~/ 4);
}

/// 估算一组 [AgentMessage] 的 token 数，遍历 content + 全部 blocks。
int estimateAgentMessagesTokens(List<AgentMessage> messages) {
  var total = 0;
  for (final msg in messages) {
    total += estimateTextTokens(msg.content);
    for (final block in msg.blocks) {
      total += _estimateBlockTokens(block);
    }
  }
  return total;
}

int _estimateBlockTokens(MessageBlock block) {
  return switch (block) {
    TextBlock(:final text) => estimateTextTokens(text),
    ThinkingBlock(:final text) => estimateTextTokens(text),
    ToolCallBlock(:final arguments) => estimateTextTokens(
      jsonEncode(arguments),
    ),
    ToolResultBlock(:final content) => content.fold(
      0,
      (sum, b) => sum + _estimateBlockTokens(b),
    ),
    ImageBlock() => 1600, // 固定估值
  };
}

/// CJK 判定：U+2E80–U+9FFF、U+F900–U+FAFF、U+FF00–U+FFEF
bool _isCjk(int rune) {
  return (rune >= 0x2E80 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFF00 && rune <= 0xFFEF);
}

/// UTF-16 代理对安全截断。
///
/// 标准 [String.substring] 按 UTF-16 code unit 切割，可能劈开代理对（emoji）
/// 产出非法字符串。本函数按 rune 边界截断，超出时追加 [suffix]。
String safeTruncate(String text, int maxChars, {String suffix = ''}) {
  if (text.length <= maxChars) return text;
  final runes = text.runes.toList(growable: false);
  if (runes.length <= maxChars) return text;
  final truncated = String.fromCharCodes(runes.sublist(0, maxChars));
  return suffix.isEmpty ? truncated : '$truncated$suffix';
}
