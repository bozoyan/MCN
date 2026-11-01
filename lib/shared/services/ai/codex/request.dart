// 职责: 统一 Codex 聊天、模型目录和生图请求的地址与认证请求头。
// 关联文件:
//   lib/shared/services/ai/codex/credentials.dart
//   lib/shared/services/ai/codex/image_client.dart
//   lib/shared/agent/client/codex_client.dart

import 'credentials.dart';

const codexBaseUrl = 'https://chatgpt.com/backend-api/codex';
const codexClientVersion = '0.159.2';

Map<String, String> codexHeaders(CodexCredentials credentials) => {
  'Authorization': 'Bearer ${credentials.accessToken}',
  'Chatgpt-Account-Id': credentials.accountId,
  'Originator': 'codex_cli_rs',
  'Version': codexClientVersion,
  'User-Agent': 'codex_cli_rs/$codexClientVersion',
  'OpenAI-Beta': 'responses=experimental',
};
