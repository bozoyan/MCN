// 职责: 保留 MCP 完整文本和结构化结果，为模型与调用记录生成限额预览。
// 关联文件:
//   lib/shared/models/mcp/call_result.dart
//   lib/shared/services/mcp/tool_dispatcher.dart
import 'dart:convert';
import '../../models/mcp/call_result.dart';

class McpResultAdapter {
  static const modelBudget = 32 * 1024;

  static McpCallResult normalize(Map<String, dynamic> raw) {
    final text = <String>[];
    final unsupported = <String>{};
    for (final item in (raw['content'] as List? ?? [])) {
      if (item is Map && item['type'] == 'text' && item['text'] is String) {
        text.add(item['text'] as String);
      } else {
        unsupported.add(item is Map ? '${item['type']}' : 'invalid');
      }
    }
    final structured = raw['structuredContent'];
    if (structured != null && structured is! Map<String, dynamic>) {
      unsupported.add('structuredContent_non_object');
    }
    final failed = raw['isError'] == true;
    return McpCallResult(
      executionState: failed
          ? McpExecutionState.failed
          : McpExecutionState.succeeded,
      text: [
        ...text,
        if (unsupported.isNotEmpty)
          '[Unsupported MCP content omitted: ${unsupported.join(', ')}]',
      ],
      structuredContent: structured is Map<String, dynamic> ? structured : null,
      errorCode: failed ? 'mcp_tool_error' : null,
      error: failed
          ? String.fromCharCodes(text.join('\n').runes.take(2048))
          : null,
    );
  }

  static McpCallResult limit(McpCallResult result, int budget) {
    if (result.jsonBytes <= budget) {
      return result;
    }
    // Only model-facing output and history previews are shortened here.
    // Full-output storage and readback are not implemented; omitted preview
    // content cannot be recovered through a result reference. Scripts receive
    // the original result before this display-only conversion.
    var structured = result.structuredContent;
    McpCallResult build(List<String> text) => McpCallResult(
      executionState: result.executionState,
      text: text,
      structuredContent: structured,
      errorCode: result.errorCode,
      error: result.error,
      cancelled: result.cancelled,
      rejected: result.rejected,
      recovery: result.ok
          ? 'The operation succeeded; this output is a truncated preview. Do not repeat a write.'
          : result.recovery,
    );
    // Keep small IDs and other structured results intact when text is large.
    // If the object itself is too large, show it as a JSON text preview instead
    // of inventing an incomplete object that looks usable by a program.
    final preview = <String>[];
    if (structured != null && build(const []).jsonBytes > budget) {
      preview.add(jsonEncode(structured));
      structured = null;
    }
    preview.addAll(result.text);
    final full = build(preview);
    if (full.jsonBytes <= budget) {
      return full;
    }
    if (build(const []).jsonBytes > budget) {
      throw ArgumentError('MCP budget is too small for host status');
    }
    final runes = preview.join('\n').runes.toList();
    String excerpt(int count) {
      final head = (count + 1) ~/ 2;
      final tail = count ~/ 2;
      return '${String.fromCharCodes(runes.take(head))}\n[truncated]\n'
          '${String.fromCharCodes(runes.skip(runes.length - tail))}';
    }

    var low = 0;
    var high = runes.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (build([excerpt(middle)]).jsonBytes <= budget) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final bounded = build([excerpt(low)]);
    return bounded.jsonBytes <= budget ? bounded : build(const []);
  }
}
