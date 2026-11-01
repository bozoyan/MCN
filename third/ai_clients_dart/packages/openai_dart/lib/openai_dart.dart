// 职责: 导出 Reveric 使用的 OpenAI Chat Completions 与 Embeddings API。
// 关联文件:
//   third/ai_clients_dart/packages/openai_dart/lib/src/client/openai_client.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/resources/chat_resource.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/resources/embeddings_resource.dart

library;

export 'src/auth/auth_provider.dart';
export 'src/client/config.dart';
export 'src/client/openai_client.dart';
export 'src/errors/exceptions.dart';
export 'src/models/chat/chat_completion.dart';
export 'src/models/chat/chat_completion_request.dart';
export 'src/models/chat/chat_message.dart';
export 'src/models/chat/content_part.dart';
export 'src/models/chat/reasoning_detail.dart';
export 'src/models/chat/tool_call.dart';
export 'src/models/embeddings/embedding_request.dart';
export 'src/models/embeddings/embedding_response.dart';
export 'src/models/responses/config/reasoning_effort.dart';
export 'src/models/streaming/chat_stream_event.dart';
export 'src/models/tools/tool.dart';
export 'src/resources/chat_resource.dart';
export 'src/resources/embeddings_resource.dart';
