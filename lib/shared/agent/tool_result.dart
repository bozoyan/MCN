// 职责: 为 JSON 工具结果携带已组装的通用模型内容块。
// 关联文件:
//   lib/shared/agent/message.dart
//   lib/shared/agent/agent.dart
import 'dart:collection';
import 'message.dart';

/// Map compatibility keeps ordinary tools unchanged. JSON iteration includes
/// only payload fields; runtime image bytes are never serialized.
class StructuredToolResult extends MapBase<String, dynamic> {
  StructuredToolResult(
    Map<String, dynamic> payload, {
    List<MessageBlock> content = const [],
  }) : _payload = Map.of(payload),
       content = List.unmodifiable(content);
  final Map<String, dynamic> _payload;
  final List<MessageBlock> content;
  @override
  Iterable<String> get keys => _payload.keys;
  @override
  dynamic operator [](Object? key) => _payload[key];
  @override
  void operator []=(String key, dynamic value) => _payload[key] = value;
  @override
  void clear() => _payload.clear();
  @override
  dynamic remove(Object? key) => _payload.remove(key);
}
