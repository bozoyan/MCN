// 职责: 聚合 OpenRouter 推理块并通过不透明 signature 保存完整回传载荷。
// 关联文件:
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/message.dart
//   lib/shared/agent/round_assembler.dart
import 'dart:convert';
import 'package:openai_dart/openai_dart.dart' show ReasoningDetail;

const _prefix = 'openrouter:reasoning_details:';

String? encodeOpenRouterReasoning(List<ReasoningDetail>? details) =>
    details == null || details.isEmpty
    ? null
    : '$_prefix${jsonEncode(details.map((d) => d.toJson()).toList())}';

List<ReasoningDetail>? decodeOpenRouterReasoning(String? signature) {
  if (signature == null || !signature.startsWith(_prefix)) {
    return null;
  }
  return (jsonDecode(signature.substring(_prefix.length)) as List)
      .map((v) => ReasoningDetail.fromJson(v as Map<String, dynamic>))
      .toList();
}

String openRouterReasoningText(List<ReasoningDetail>? details) =>
    (details ?? const <ReasoningDetail>[])
        .map((d) => d.text ?? d.summary ?? '')
        .join();

class OpenRouterReasoningAccumulator {
  final _details = <Map<String, dynamic>>[];

  void add(List<ReasoningDetail>? deltas) {
    for (final delta in deltas ?? const <ReasoningDetail>[]) {
      final json = delta.toJson();
      final position = _details.indexWhere(
        (d) =>
            d['type'] == delta.type &&
            (delta.index != null
                ? d['index'] == delta.index
                : delta.id != null && d['id'] == delta.id),
      );
      if (position < 0) {
        _details.add(json);
        continue;
      }
      final existing = _details[position];
      for (final entry in json.entries) {
        if (const {
              'text',
              'summary',
              'data',
              'signature',
            }.contains(entry.key) &&
            existing[entry.key] is String &&
            entry.value is String) {
          existing[entry.key] = '${existing[entry.key]}${entry.value}';
        } else {
          existing[entry.key] = entry.value;
        }
      }
    }
  }

  String? get signature => encodeOpenRouterReasoning(
    _details.map(ReasoningDetail.fromJson).toList(),
  );
}
