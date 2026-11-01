// 职责: Agent round 组装测试 — 验证 provider stream 取消不会误报工具参数截断
// 关联文件:
//   lib/shared/agent/round_assembler.dart
//   lib/shared/agent/client.dart
//   lib/shared/agent/agent_event.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/round_assembler.dart';

void main() {
  group('assembleRound', () {
    test(
      'does not emit incomplete tool call when provider stream is cancelled',
      () async {
        final events = await assembleRound(
          Stream<StreamEvent>.fromIterable([
            ToolCallDelta(
              callId: 'toolu_1',
              toolName: 'Read',
              arguments: const {'path': '/tmp'},
              isPartial: true,
            ),
            StreamCancelled(),
          ]),
        ).toList();

        expect(events.whereType<AgentRoundToolCallDelta>(), hasLength(1));
        expect(events.whereType<AgentRoundToolCallIncomplete>(), isEmpty);
        expect(events.whereType<AgentRoundComplete>(), isEmpty);
      },
    );

    test(
      'partial tool call at stream end is dropped and the round still completes',
      () async {
        final events = await assembleRound(
          Stream<StreamEvent>.fromIterable([
            ToolCallDelta(
              callId: 'toolu_partial',
              toolName: 'Edit',
              arguments: const {'path': '/chapters/1'},
              isPartial: true,
            ),
            StreamComplete(),
          ]),
        ).toList();

        expect(events.whereType<AgentRoundToolCallIncomplete>(), hasLength(1));
        expect(events.whereType<AgentRoundComplete>(), hasLength(1));
        expect(
          events.whereType<AgentRoundComplete>().single.result.toolCalls,
          isEmpty,
        );
      },
    );

    test('keeps completed tool calls and drops the partial one', () async {
      // 已完成的调用是有效产出，不该因为最后一个没收完就整轮作废重来。
      final events = await assembleRound(
        Stream<StreamEvent>.fromIterable([
          ToolCallDelta(
            callId: 'toolu_a',
            toolName: 'Read',
            arguments: const {'path': '/chapters/1'},
            isPartial: false,
          ),
          ToolCallDelta(
            callId: 'toolu_b',
            toolName: 'Read',
            arguments: const {'path': '/chapters/2'},
            isPartial: false,
          ),
          ToolCallDelta(
            callId: 'toolu_c',
            toolName: 'Edit',
            arguments: const {'path': '/chapters/3'},
            isPartial: true,
          ),
          StreamComplete(),
        ]),
      ).toList();

      // 半截的那个要显式通知上层，UI 才能把已渲染的卡片标成 incomplete。
      final incomplete = events
          .whereType<AgentRoundToolCallIncomplete>()
          .single;
      expect(incomplete.request.callId, 'toolu_c');

      final complete = events.whereType<AgentRoundComplete>().single;
      expect(complete.result.toolCalls.map((c) => c.callId), [
        'toolu_a',
        'toolu_b',
      ]);
    });

    test('length truncation yields a round instead of throwing', () async {
      // 半截 tool 一律交出 round，不按 finishReason 整轮作废。
      final events = await assembleRound(
        Stream<StreamEvent>.fromIterable([
          TextDelta('已经写了一半'),
          ToolCallDelta(
            callId: 'toolu_truncated',
            toolName: 'Create',
            arguments: const {'path': '/chapters'},
            isPartial: true,
          ),
          StreamComplete(finishReason: StreamFinishReason.length),
        ]),
      ).toList();

      expect(events.whereType<AgentRoundToolCallIncomplete>(), hasLength(1));
      final complete = events.whereType<AgentRoundComplete>().single;
      expect(complete.result.finishReason, StreamFinishReason.length);
      expect(complete.result.text, '已经写了一半');
      // 半截参数绝不能当成可执行的 tool call 交出去。
      expect(complete.result.toolCalls, isEmpty);
    });

    test('carries thinking signature into round result', () async {
      final events = await assembleRound(
        Stream<StreamEvent>.fromIterable([
          ThinkingDelta('reasoning'),
          SignatureDelta('sig123'),
          TextDelta('answer'),
          StreamComplete(),
        ]),
      ).toList();

      final complete = events.whereType<AgentRoundComplete>().single;
      expect(complete.result.thinking, 'reasoning');
      expect(complete.result.thinkingSignature, 'sig123');
    });

    test('carries every encrypted reasoning item into round result', () async {
      final events = await assembleRound(
        Stream<StreamEvent>.fromIterable([
          EncryptedContentDelta('enc_a'),
          EncryptedContentDelta(''),
          EncryptedContentDelta('enc_b'),
          StreamComplete(),
        ]),
      ).toList();

      final complete = events.whereType<AgentRoundComplete>().single;
      expect(complete.result.encryptedContents, ['enc_a', 'enc_b']);
    });

    test('carries the provider finish reason into the round result', () async {
      final events = await assembleRound(
        Stream<StreamEvent>.fromIterable([
          ThinkingDelta('reasoning'),
          StreamComplete(finishReason: StreamFinishReason.length),
        ]),
      ).toList();

      final complete = events.whereType<AgentRoundComplete>().single;
      expect(complete.result.finishReason, StreamFinishReason.length);
    });
  });
}
