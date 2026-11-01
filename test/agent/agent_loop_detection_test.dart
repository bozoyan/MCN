// 职责: Agent 循环检测集成测试 — 验证前置 abort、hint 注入、上下文闭合
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/loop_detector.dart
//   lib/shared/agent/fake_agent.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';

/// 每次调用都返回相同的 tool call（模拟死循环 LLM）。
FakeProviderClientResponse _sameToolCallResponse(
  String toolName,
  String callId,
) {
  return FakeProviderClientResponse.toolCalls([
    ToolCall(
      callId: callId,
      toolName: toolName,
      arguments: const {'path': '/same'},
    ),
  ]);
}

void main() {
  group('Agent loop detection — pre-emptive abort', () {
    test(
      '5 consecutive identical tool calls → abort, tool not executed 5th time',
      () async {
        // LLM 每轮都返回相同的 tool call。连续 5 次达 abort 阈值。
        // 注意：前置检测意味着第 5 次 tool call 在执行前就被拦截。
        // 前 3 次正常执行（hint 阈值 3），第 4 次注入 hint 后也执行（因为第 3 次是
        // 先 record 再 check，第 3 次 check 命中 hint → 不执行 → 注入 hint → continue）。
        // 实际时序：
        //   round 1: record A, check(1) null, execute A ✓
        //   round 2: record A, check(2) null, execute A ✓
        //   round 3: record A, check(3) hint! → skip A, inject hint, continue
        //   round 4: record A, check(4) hint! but hintInjected → abort
        // 所以 tool 实际执行 2 次。
        final client = FakeProviderClient(
          responder: (_) {
            return _sameToolCallResponse('Read', 'call_loop');
          },
        );
        final dispatcher = FakeAgentToolDispatcher.withResults(
          results: {
            'Read': {'ok': true, 'content': 'file content'},
          },
        );
        final ctxMgr = SimpleAgentContextManager();
        final agent = Agent.custom(
          id: 'test',
          systemPrompt: 'Be helpful.',
          client: client,
          config: const AgentConfig(),
          toolManager: dispatcher,
          contextManager: ctxMgr,
        );

        final events = await agent.process('read the file repeatedly').toList();

        // 应该有 AgentLoopDetected 事件
        expect(events.whereType<AgentLoopDetected>(), isNotEmpty);
        // 应该有 AgentDone（终止）
        expect(events.whereType<AgentDone>(), isNotEmpty);

        // tool 实际执行次数应该 < 5（前置检测拦截了后续）
        expect(
          dispatcher.capturedCalls.length,
          lessThan(5),
          reason: '前置检测应在达 abort 阈值前拦截重复 tool call',
        );
      },
    );

    test(
      'context remains closed after loop abort — every tool_call has a tool_result',
      () async {
        final client = FakeProviderClient(
          responder: (_) {
            return _sameToolCallResponse('Read', 'call_loop');
          },
        );
        final dispatcher = FakeAgentToolDispatcher.withResults(
          results: {
            'Read': {'ok': true, 'content': 'file content'},
          },
        );
        final ctxMgr = SimpleAgentContextManager();
        final agent = Agent.custom(
          id: 'test',
          systemPrompt: 'Be helpful.',
          client: client,
          config: const AgentConfig(),
          toolManager: dispatcher,
          contextManager: ctxMgr,
        );

        await agent.process('read the file repeatedly').toList();

        // 验证上下文闭合：每个 assistant 消息中的 ToolCallBlock 都有配对的 tool_result。
        final messages = ctxMgr.messages;
        final toolCallIds = <String>[];
        for (final msg in messages) {
          if (msg.role == AgentMessageRole.assistant) {
            for (final block in msg.blocks.whereType<ToolCallBlock>()) {
              toolCallIds.add(block.callId);
            }
          }
        }
        final toolResultIds = <String>{};
        for (final msg in messages) {
          if (msg.type == AgentMessageType.tool_result) {
            for (final block in msg.blocks.whereType<ToolResultBlock>()) {
              toolResultIds.add(block.toolCallId);
            }
          }
        }

        for (final callId in toolCallIds) {
          expect(
            toolResultIds.contains(callId),
            isTrue,
            reason: 'tool_call $callId 没有配对的 tool_result，上下文断裂',
          );
        }
      },
    );

    test('skipped tool calls produce placeholder tool_result', () async {
      final client = FakeProviderClient(
        responder: (_) {
          return _sameToolCallResponse('Read', 'call_loop');
        },
      );
      final dispatcher = FakeAgentToolDispatcher.withResults(
        results: {
          'Read': {'ok': true, 'content': 'file content'},
        },
      );
      final ctxMgr = SimpleAgentContextManager();
      final agent = Agent.custom(
        id: 'test',
        systemPrompt: 'Be helpful.',
        client: client,
        config: const AgentConfig(),
        toolManager: dispatcher,
        contextManager: ctxMgr,
      );

      await agent.process('read the file repeatedly').toList();

      // 应该存在被 skip 的 tool_result（loop_skipped error_code）
      final toolResultMsgs = ctxMgr.messages
          .where((m) => m.type == AgentMessageType.tool_result)
          .toList();
      var foundSkipped = false;
      for (final msg in toolResultMsgs) {
        final block = msg.blocks.whereType<ToolResultBlock>().firstOrNull;
        if (block == null) continue;
        final text = block.content.whereType<TextBlock>().firstOrNull?.text;
        if (text == null) continue;
        if (text.contains('loop_skipped')) {
          foundSkipped = true;
          expect(block.isError, isTrue);
          break;
        }
      }
      expect(foundSkipped, isTrue, reason: '应存在被循环检测 skip 的 tool_result');
    });
  });

  group('Agent loop detection — hint injection', () {
    test(
      'hint injected after 3 consecutive, model recovers → no abort',
      () async {
        // LLM 前 3 轮返回相同 tool call，第 4 轮起返回文本（模拟模型收到提示后纠正）。
        var callCount = 0;
        final client = FakeProviderClient(
          responder: (_) {
            callCount++;
            if (callCount <= 2) {
              return _sameToolCallResponse('Read', 'call_loop');
            }
            // 第 3 轮仍返回相同 tool call → hint 命中
            if (callCount == 3) {
              return _sameToolCallResponse('Read', 'call_loop');
            }
            // 第 4 轮起返回文本（模型收到提示后纠正）
            return const FakeProviderClientResponse.text(
              'I will try a different approach.',
            );
          },
        );
        final dispatcher = FakeAgentToolDispatcher.withResults(
          results: {
            'Read': {'ok': true, 'content': 'file content'},
          },
        );
        final ctxMgr = SimpleAgentContextManager();
        final agent = Agent.custom(
          id: 'test',
          systemPrompt: 'Be helpful.',
          client: client,
          config: const AgentConfig(),
          toolManager: dispatcher,
          contextManager: ctxMgr,
        );

        final events = await agent.process('read the file').toList();

        // 应该有 AgentLoopDetected（hint 级别）
        expect(events.whereType<AgentLoopDetected>(), isNotEmpty);

        // 应该有 AgentDone 且最终文本是模型纠正后的回复
        final done = events.whereType<AgentDone>().firstOrNull;
        expect(done, isNotNull);
        expect(done!.finalText, contains('different approach'));

        // 上下文中应有 hint 提示消息
        final hintMsgs = ctxMgr.messages.where(
          (m) => m.content.contains('repeating the same tool call'),
        );
        expect(hintMsgs, isNotEmpty, reason: '应注入循环提示消息');
      },
    );
  });

  group('Agent loop detection — context closure after hint', () {
    test('hint path also keeps context closed', () async {
      var callCount = 0;
      final client = FakeProviderClient(
        responder: (_) {
          callCount++;
          if (callCount <= 3) {
            return _sameToolCallResponse('Read', 'call_loop');
          }
          return const FakeProviderClientResponse.text('recovered');
        },
      );
      final dispatcher = FakeAgentToolDispatcher.withResults(
        results: {
          'Read': {'ok': true, 'content': 'content'},
        },
      );
      final ctxMgr = SimpleAgentContextManager();
      final agent = Agent.custom(
        id: 'test',
        systemPrompt: 'Be helpful.',
        client: client,
        config: const AgentConfig(),
        toolManager: dispatcher,
        contextManager: ctxMgr,
      );

      await agent.process('read file').toList();

      // 验证上下文闭合
      final messages = ctxMgr.messages;
      final toolCallIds = <String>[];
      for (final msg in messages) {
        if (msg.role == AgentMessageRole.assistant) {
          for (final block in msg.blocks.whereType<ToolCallBlock>()) {
            toolCallIds.add(block.callId);
          }
        }
      }
      final toolResultIds = <String>{};
      for (final msg in messages) {
        if (msg.type == AgentMessageType.tool_result) {
          for (final block in msg.blocks.whereType<ToolResultBlock>()) {
            toolResultIds.add(block.toolCallId);
          }
        }
      }
      for (final callId in toolCallIds) {
        expect(
          toolResultIds.contains(callId),
          isTrue,
          reason: 'hint 路径也应保持上下文闭合，tool_call $callId 缺配对 result',
        );
      }
    });
  });
}
