// 职责: 解析 New API 模型端点元数据并选择受支持的聊天协议。
// 关联文件:
//   lib/shared/services/ai/new_api.dart
//   lib/shared/models/ai_provider.dart

enum NewApiChatProtocol { responses, anthropic, gemini, openai }

class NewApiModel {
  const NewApiModel({required this.id, required this.endpointTypes});
  final String id;
  final Set<String> endpointTypes;

  factory NewApiModel.fromJson(Map<String, dynamic> json) => NewApiModel(
    id: json['id'] as String,
    endpointTypes: (json['supported_endpoint_types'] as List? ?? [])
        .cast<String>()
        .toSet(),
  );

  NewApiChatProtocol get chatProtocol {
    final name = id.toLowerCase().split('/').last;
    final preferred = name.startsWith('claude-')
        ? NewApiChatProtocol.anthropic
        : name.startsWith('gemini-')
        ? NewApiChatProtocol.gemini
        : name.startsWith('gpt-') || RegExp(r'^o[134](?:-|$)').hasMatch(name)
        ? NewApiChatProtocol.responses
        : NewApiChatProtocol.openai;
    const endpoints = {
      NewApiChatProtocol.responses: 'openai-response',
      NewApiChatProtocol.anthropic: 'anthropic',
      NewApiChatProtocol.gemini: 'gemini',
      NewApiChatProtocol.openai: 'openai',
    };
    // Select from the server's advertised capabilities before sending a turn.
    // OpenAI chat is the generic contract for renamed models on a gateway.
    for (final protocol in [
      preferred,
      NewApiChatProtocol.openai,
      NewApiChatProtocol.responses,
      NewApiChatProtocol.anthropic,
      NewApiChatProtocol.gemini,
    ]) {
      if (endpointTypes.contains(endpoints[protocol])) {
        return protocol;
      }
    }
    throw UnsupportedError('No supported chat endpoint for New API model: $id');
  }
}
