// 职责: 验证供应商聊天客户端的协议、国内固定路由、网关地址与权限门禁。
// 关联文件:
//   lib/shared/services/ai/provider_initializer.dart

import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/services/ai/provider_initializer.dart';
import 'package:reveric/shared/models/ai_provider.dart';

void main() {
  test('AtlasCloud reuses Chat Completions with its account key', () async {
    final provider = aiProviderBuiltinById(
      'openai',
    )!.copyWith(type: 'atlascloud', apiKey: 'atlas-key');
    final initializer = AiProviderInitializer(
      config: provider,
      chatModel: 'deepseek-ai/deepseek-v3.2',
      httpClient: MockClient((r) async {
        expect(
          r.url.toString(),
          'https://api.atlascloud.ai/v1/chat/completions',
        );
        expect(r.headers['Authorization'], 'Bearer atlas-key');
        expect(
          (jsonDecode(r.body) as Map)['model'],
          'deepseek-ai/deepseek-v3.2',
        );
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(initializer.dispose);
    final api = await initializer.initialize();
    await api.chat(
      messages: [AgentMessage.user(id: 'user', content: 'hello')],
    );
  });
  test(
    'Volcengine chat uses the fixed domestic Ark route and shared API key',
    () async {
      final provider = aiProviderBuiltinById('doubao')!.copyWith(
        type: 'volcengine',
        baseUrl: 'https://override.example/v1',
        apiKey: 'shared-key',
      );
      final initializer = AiProviderInitializer(
        config: provider,
        chatModel: provider.models.first,
        httpClient: MockClient((r) async {
          expect(
            r.url.toString(),
            'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
          );
          expect(r.headers['Authorization'], 'Bearer shared-key');
          expect((jsonDecode(r.body) as Map)['model'], provider.models.first);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(initializer.dispose);
      final api = await initializer.initialize();
      await api.chat(
        messages: [AgentMessage.user(id: 'user', content: 'hello')],
      );
    },
  );
  test('Qwen custom URL uses Chat Completions and enable_thinking', () async {
    final provider = aiProviderBuiltinById('openai')!.copyWith(
      type: 'qwen',
      baseUrl: 'https://proxy.example/prefix/compatible-mode/v1',
      apiKey: 'qwen-key',
    );
    expect(provider.hasFixedBaseUrl, false);
    final initializer = AiProviderInitializer(
      config: provider,
      chatModel: 'qwen3.8-flash',
      httpClient: MockClient((r) async {
        expect(
          r.url.toString(),
          'https://proxy.example/prefix/compatible-mode/v1/chat/completions',
        );
        expect(r.headers['Authorization'], 'Bearer qwen-key');
        final body = jsonDecode(r.body) as Map;
        expect(body['enable_thinking'], false);
        expect(body.containsKey('thinking'), false);
        expect(body.containsKey('reasoning_effort'), false);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final api = await initializer.initialize();
    await api.chat(
      messages: [AgentMessage.user(id: 'user', content: 'hello')],
      options: const AgentConfig(reasoningEffort: 'none'),
    );
    initializer.dispose();
  });
  test('Qwen default replaces only blank and known former fixed URL', () {
    for (final old in ['', 'https://dashscope.aliyuncs.com/apps/anthropic/']) {
      final provider = aiProviderBuiltinById(
        'openai',
      )!.copyWith(type: 'qwen', baseUrl: old, apiKey: 'existing-key');
      expect(provider.effectiveBaseUrl, qwenDefaultBaseUrl);
      expect(provider.apiKey, 'existing-key');
      expect(provider.hasBaseUrl, true);
    }
    expect(
      qwenBaseUrl('https://custom.example/proxy/v1'),
      'https://custom.example/proxy/v1',
    );
  });
  test('Gemini gateway base URL strips the OpenAI v1 suffix', () {
    expect(
      geminiGatewayBaseUrl('http://localhost:9010/v1'),
      'http://localhost:9010',
    );
  });

  test(
    'initializes a configured third-party provider without an account',
    () async {
      final provider = aiProviderBuiltinById(
        'deepseek',
      )!.copyWith(apiKey: 'test-key', enabled: true);
      final initializer = AiProviderInitializer(
        config: provider,
        chatModel: provider.models.first,
      );

      addTearDown(initializer.dispose);
      await expectLater(initializer.initialize(), completes);
    },
  );
}
