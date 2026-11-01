// 职责: Fake Agent 测试 — 验证 fake client、fake tool dispatcher 与快速创建 Agent 的测试辅助能力
// 关联文件:
//   lib/shared/agent/fake_agent.dart
//   lib/shared/agent/agent.dart
//   lib/shared/agent/client.dart
//   lib/shared/agent/message.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';

void main() {
  group('FakeProviderClient', () {
    test('returns fixed chat and stream responses', () async {
      final client = FakeProviderClient(
        responses: const [
          FakeProviderClientResponse.text(
            'fixed answer',
            thinking: 'fixed thinking',
            usage: AiUsage(inputTokens: 3, outputTokens: 4),
          ),
        ],
      );

      final chat = await client.chat(messages: const []);
      final stream = await client.chatStream(messages: const []).toList();

      expect(chat.text, 'fixed answer');
      expect(chat.thinking, 'fixed thinking');
      expect(chat.usage, const AiUsage(inputTokens: 3, outputTokens: 4));
      expect(stream.whereType<ThinkingDelta>().single.text, 'fixed thinking');
      expect(stream.whereType<TextDelta>().single.text, 'fixed answer');
      expect(
        stream.whereType<StreamComplete>().single.usage,
        const AiUsage(inputTokens: 3, outputTokens: 4),
      );
      expect(client.capturedChatRequests, hasLength(1));
      expect(client.capturedStreamRequests, hasLength(1));
    });

    test('supports custom response data per call', () async {
      final client = FakeProviderClient(
        repeatLastResponse: false,
        responder: (request) {
          return FakeProviderClientResponse.text(
            'round ${request.callIndex}: ${request.messages.last.content}',
          );
        },
      );

      final first = await client.chat(
        messages: [AgentMessage.user(id: 'user_1', content: 'first')],
      );
      final second = await client.chat(
        messages: [AgentMessage.user(id: 'user_2', content: 'second')],
      );

      expect(first.text, 'round 0: first');
      expect(second.text, 'round 1: second');
    });
  });

  group('FakeAgent', () {
    test('creates a runnable Agent that produces configured data', () async {
      final agent = FakeAgent.create(
        responses: const [FakeProviderClientResponse.text('generated data')],
      );

      final events = await agent.process('produce data').toList();

      expect(events.whereType<AgentRoundText>().single.text, 'generated data');
      expect(events.whereType<AgentDone>().single.finalText, 'generated data');
    });

    test(
      'supports custom tool data and continues to the next response',
      () async {
        final toolDispatcher = FakeAgentToolDispatcher(
          tools: {
            'ReadFixture': FakeAgentTool(
              def: const ToolDef(
                name: 'ReadFixture',
                description: 'Reads fake fixture data.',
                inputSchema: {'type': 'object'},
              ),
              handler: (input, callId) => {
                'ok': true,
                'fixture': input['name'],
                'call_id': callId,
              },
            ),
          },
        );
        final client = FakeProviderClient(
          responses: const [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'call_fixture',
                toolName: 'ReadFixture',
                arguments: {'name': 'chapter'},
              ),
            ]),
            FakeProviderClientResponse.text('used fixture data'),
          ],
        );
        final agent = FakeAgent.create(
          client: client,
          toolManager: toolDispatcher,
        );

        final context = ToolExecutionContext(
          sourceSessionId: 'session_1',
          sourceTurnId: 'turn_1',
        );
        final events = await agent
            .process('load fixture', toolExecutionContext: context)
            .toList();

        expect(
          events.whereType<AgentDone>().single.finalText,
          'used fixture data',
        );
        expect(toolDispatcher.capturedCalls, hasLength(1));
        expect(toolDispatcher.capturedCalls.single.name, 'ReadFixture');
        expect(toolDispatcher.capturedCalls.single.input, {'name': 'chapter'});
        expect(toolDispatcher.capturedCalls.single.context, same(context));

        final secondRoundMessages = client.capturedStreamRequests[1].messages;
        final toolResult = secondRoundMessages.singleWhere(
          (message) => message.type == AgentMessageType.tool_result,
        );
        final block = toolResult.blocks.single as ToolResultBlock;
        final payload =
            jsonDecode((block.content.single as TextBlock).text)
                as Map<String, dynamic>;
        expect(payload['fixture'], 'chapter');
        expect(payload['call_id'], 'call_fixture');
      },
    );
  });
}
