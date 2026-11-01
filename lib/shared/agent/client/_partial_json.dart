// 职责: 流式工具调用 partial JSON 容错解析 — 在尚未闭合的 JSON 串中尽力取出已有字段
// 关联文件:
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/openai_responses_client.dart

import 'dart:convert';

final _trailingStringValue = RegExp(
  r'^(.*?)("(?:[^"\\]|\\.)*"\s*)$',
  dotAll: true,
);

Map<String, dynamic> parseStreamingJson(String s) {
  if (s.isEmpty) return const {};
  final direct = tryDecodeJsonObject(s);
  if (direct != null) return direct;

  final stack = <String>[];
  var inString = false;
  var escape = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      stack.add('}');
    } else if (ch == '[') {
      stack.add(']');
    } else if (ch == '}' || ch == ']') {
      if (stack.isNotEmpty && stack.last == ch) stack.removeLast();
    }
  }

  var out = s;
  if (inString) out += '"';

  var changed = true;
  while (changed) {
    changed = false;
    final trimmed = _stripTrailingSeparator(out);
    if (trimmed != out) {
      out = trimmed;
      changed = true;
      continue;
    }
    final m = _trailingStringValue.firstMatch(out);
    if (m != null) {
      final prefix = _stripTrailingWhitespace(m.group(1)!);
      if (prefix.endsWith(',') ||
          prefix.endsWith('{') ||
          prefix.endsWith('[')) {
        out = m.group(1)!;
        changed = true;
      }
    }
  }

  for (final c in stack.reversed) {
    out += c;
  }

  return tryDecodeJsonObject(out) ?? const {};
}

/// 仅当 [s] 本身是完整 JSON object 时返回解码值，不修补未闭合内容。
Map<String, dynamic>? tryDecodeJsonObject(String s) {
  try {
    final value = jsonDecode(s);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

/// Removes trailing JSON separators (`,`, `:`, whitespace) by a single backward
/// pass — avoids `replaceFirst(RegExp)` on the hot path.
String _stripTrailingSeparator(String s) {
  var end = s.length;
  while (end > 0) {
    final cu = s.codeUnitAt(end - 1);
    if (cu == 0x2c /* , */ ||
        cu == 0x3a /* : */ ||
        cu == 0x20 /* space */ ||
        cu == 0x09 /* \t */ ||
        cu == 0x0a /* \n */ ||
        cu == 0x0d /* \r */ ) {
      end--;
    } else {
      break;
    }
  }
  return end < s.length ? s.substring(0, end) : s;
}

/// Removes trailing whitespace characters by a single backward pass.
String _stripTrailingWhitespace(String s) {
  var end = s.length;
  while (end > 0) {
    final cu = s.codeUnitAt(end - 1);
    if (cu == 0x20 /* space */ ||
        cu == 0x09 /* \t */ ||
        cu == 0x0a /* \n */ ||
        cu == 0x0d /* \r */ ) {
      end--;
    } else {
      break;
    }
  }
  return end < s.length ? s.substring(0, end) : s;
}
