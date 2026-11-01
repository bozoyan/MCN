// 职责: Trace headers http client — 包装 http.Client 自动添加 x-session-id / x-session-parent-id / x-session-mode headers
// 关联文件:
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/gemini_client.dart

import 'dart:async';

import 'package:http/http.dart' as http;

typedef TraceHeadersProvider = Map<String, String> Function();

/// 按子会话 id 构建 trace headers；多角色场景每个参与者一条子会话。
typedef SubSessionTraceHeadersProvider =
    Map<String, String> Function(String subSessionId);

/// 构建 AI 请求的 session trace headers（供各 AiClient 使用方传入）。
///
/// [sessionId] 是本次请求归属的会话。SubAgent 这类派生会话传自己的子会话 id，
/// 并用 [parentSessionId] 指向派生它的会话；不传 [parentSessionId] 时 parent 头
/// 回落为 [sessionId] 自身，表示这是一条顶层会话。
Map<String, String> buildTraceSessionHeaders({
  String? sessionId,
  String? parentSessionId,
  required String sessionMode,
}) {
  final headers = <String, String>{'x-session-mode': sessionMode};
  if (sessionId != null && sessionId.isNotEmpty) {
    headers['x-session-id'] = sessionId;
    headers['x-session-parent-id'] =
        parentSessionId != null && parentSessionId.isNotEmpty
        ? parentSessionId
        : sessionId;
  }
  return headers;
}

/// 派生仅用于 trace 归属的子会话 id。
///
/// 剧场、议事这类多角色场景里每个参与者算一条子会话：由父会话 id 与参与者 id
/// 拼出，同一参与者跨轮次、跨续演都得到同一个 id，上游才能串起它的完整线索。
/// 该 id 只出现在 trace 头里，不落库，也不参与本地 usage / trace 上报。
/// 任一入参为空时返回空串，调用方据此回退到父会话。
String buildTraceSubSessionId({
  required String parentSessionId,
  required String participantId,
}) {
  if (parentSessionId.isEmpty || participantId.isEmpty) {
    return '';
  }
  return 'sub_${parentSessionId}_$participantId';
}

class TraceHeadersHttpClient extends http.BaseClient {
  final http.Client _inner;
  final TraceHeadersProvider _headersProvider;

  TraceHeadersHttpClient({
    required this._inner,
    required this._headersProvider,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final traceHeaders = _headersProvider();
    for (final entry in traceHeaders.entries) {
      request.headers[entry.key] = entry.value;
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
