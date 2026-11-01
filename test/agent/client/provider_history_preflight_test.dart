// 职责: 验证 provider 出站历史在发网前拒绝空 ID、重复 ID、缺失/孤立/错序 tool result。
// 关联文件:
//   lib/shared/agent/client/provider_history_preflight.dart
//   lib/shared/agent/message.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/client/provider_history_preflight.dart';
import 'package:reveric/shared/agent/message.dart';

const _callA = ToolCallBlock(
  callId: 'call_a',
  toolName: 'Read',
  arguments: {'path': '/novel'},
);

AgentMessage _assistantCalls(List<ToolCallBlock> calls) {
  return AgentMessage(
    id: 'assistant_calls',
    role: AgentMessageRole.assistant,
    blocks: calls,
  );
}

AgentMessage _toolResults(
  List<ToolResultBlock> results, {
  String id = 'tools',
}) {
  return AgentMessage(
    id: id,
    role: AgentMessageRole.user,
    type: AgentMessageType.tool_result,
    blocks: results,
  );
}

ToolResultBlock _result(String callId, {String toolName = 'Read'}) {
  return ToolResultBlock(
    toolCallId: callId,
    toolName: toolName,
    content: const [TextBlock('result')],
  );
}

ProviderHistoryValidationException _capture(
  List<AgentMessage> messages, {
  ProviderHistoryPolicy policy = ProviderHistoryPolicy.openAiChat,
}) {
  try {
    preflightProviderHistory(messages, policy);
  } on ProviderHistoryValidationException catch (error) {
    return error;
  }
  throw StateError('Expected ProviderHistoryValidationException');
}

void main() {
  test('all provider policies accept paired parallel tool calls', () {
    final messages = [
      _assistantCalls(const [
        _callA,
        ToolCallBlock(
          callId: 'call_b',
          toolName: 'Glob',
          arguments: {'pattern': '*'},
        ),
      ]),
      _toolResults([_result('call_a')], id: 'result_a'),
      _toolResults([_result('call_b', toolName: 'Glob')], id: 'result_b'),
      AgentMessage.user(id: 'user_after_tools', content: 'continue'),
    ];

    for (final policy in const [
      ProviderHistoryPolicy.openAiChat,
      ProviderHistoryPolicy.openAiResponses,
      ProviderHistoryPolicy.anthropic,
      ProviderHistoryPolicy.gemini,
    ]) {
      expect(() => preflightProviderHistory(messages, policy), returnsNormally);
    }
  });

  test('rejects an empty tool call id', () {
    final error = _capture([
      _assistantCalls(const [
        ToolCallBlock(callId: ' ', toolName: 'Read', arguments: {}),
      ]),
    ]);

    expect(error.issue, ProviderHistoryIssue.emptyToolCallId);
    expect(error.messageIndex, 0);
    expect(error.blockIndex, 0);
  });

  test('rejects an empty tool result id', () {
    final error = _capture([
      _assistantCalls(const [_callA]),
      _toolResults([_result('')]),
    ]);

    expect(error.issue, ProviderHistoryIssue.emptyToolResultId);
    expect(error.messageIndex, 1);
  });

  test('rejects duplicate tool call ids', () {
    final error = _capture([
      _assistantCalls(const [
        _callA,
        ToolCallBlock(callId: 'call_a', toolName: 'Glob', arguments: {}),
      ]),
    ]);

    expect(error.issue, ProviderHistoryIssue.duplicateToolCallId);
    expect(error.blockIndex, 1);
    expect(error.duplicateOfMessageIndex, 0);
    expect(error.duplicateOfBlockIndex, 0);
    expect(error.sameMessageId, isTrue);
    expect(error.sameToolName, isFalse);
    expect(error.sameArguments, isFalse);
  });

  test(
    'cross-round duplicate diagnostics distinguish replay from reused ID',
    () {
      for (final replay in [true, false]) {
        final error = _capture([
          _assistantCalls(const [_callA]),
          _toolResults([_result(_callA.callId)]),
          AgentMessage(
            id: replay ? 'assistant_calls' : 'later_message',
            role: AgentMessageRole.assistant,
            blocks: [
              ToolCallBlock(
                callId: _callA.callId,
                toolName: 'Read',
                arguments: replay
                    ? _callA.arguments
                    : const {'path': 'private path'},
              ),
            ],
          ),
        ], policy: ProviderHistoryPolicy.gemini);
        expect(error.messageIndex, 2);
        expect(error.duplicateOfMessageIndex, 0);
        expect(error.sameMessageId, replay);
        expect(error.sameToolName, isTrue);
        expect(error.sameArguments, replay);
        expect(error.toString(), contains('duplicate_of_message_index=0'));
        expect(error.toString(), isNot(contains('private path')));
        expect(error.toString(), isNot(contains(_callA.callId)));
      }
    },
  );

  test('rejects a tool result without a preceding call', () {
    final error = _capture([
      _toolResults([_result('orphan')]),
    ]);

    expect(error.issue, ProviderHistoryIssue.orphanToolResult);
    expect(error.pendingCallCount, 0);
  });

  test('rejects an assistant call without a result', () {
    final error = _capture([
      _assistantCalls(const [_callA]),
    ]);

    expect(error.issue, ProviderHistoryIssue.missingToolResult);
    expect(error.messageIndex, 0);
    expect(error.pendingCallCount, 1);
  });

  test('rejects ordinary messages inserted before pending results', () {
    final error = _capture([
      _assistantCalls(const [_callA]),
      AgentMessage.user(id: 'user_too_early', content: 'interrupt'),
      _toolResults([_result('call_a')]),
    ]);

    expect(error.issue, ProviderHistoryIssue.toolResultOutOfOrder);
    expect(error.messageIndex, 1);
  });

  test('exception text contains only structural diagnostics', () {
    final error = _capture([
      _assistantCalls(const [
        ToolCallBlock(
          callId: 'secret-tool-id',
          toolName: 'Read',
          arguments: {'secret': 'private content'},
        ),
      ]),
    ], policy: ProviderHistoryPolicy.anthropic);

    final text = error.toString();
    expect(text, contains('protocol=anthropic'));
    expect(text, contains('issue=missing_tool_result'));
    expect(text, isNot(contains('secret-tool-id')));
    expect(text, isNot(contains('private content')));
  });
}
