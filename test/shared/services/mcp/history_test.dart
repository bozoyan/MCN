// 职责: 验证 MCP 身份与执行事实可恢复，恢复过程不依赖当前工具目录。
// 关联文件:
//   lib/shared/models/ai_message_block.dart
//   lib/shared/models/ai_nested_tool_call.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_message_block.dart';

void main() {
  test(
    'deleted server history preserves source and unknown execution without a runtime',
    () {
      const block = AiToolCallBlock(
        id: 'block',
        callId: 'parent',
        toolName: 'Codemode',
        arguments: {'code': 'text("saved")'},
        status: AiToolCallStatus.success,
        nestedCalls: [
          AiNestedToolCall(
            callId: 'child',
            toolName: 'mcp__old__write',
            source: 'mcp',
            server: 'old',
            remoteToolName: 'write',
            sourceSessionId: 'session',
            parentCallId: 'parent',
            executionState: 'unknown',
            effectStatus: AiToolEffectStatus.unknown,
            status: AiNestedToolStatus.cancelled,
            resultPreview: '{"ok":false,"executionState":"unknown"}',
          ),
        ],
      );
      final restored = AiToolCallBlock.fromJson(
        jsonDecode(jsonEncode(block.toJson())) as Map<String, dynamic>,
      );
      final call = restored.nestedCalls.single;
      expect(call.source, 'mcp');
      expect(call.server, 'old');
      expect(call.remoteToolName, 'write');
      expect(call.sourceSessionId, 'session');
      expect(call.parentCallId, 'parent');
      expect(call.executionState, 'unknown');
      expect(call.effectStatus, AiToolEffectStatus.unknown);
    },
  );
  test(
    'old builtin records retain defaults and top-level MCP metadata survives',
    () {
      final old = AiNestedToolCall.fromJson({
        'call_id': 'old',
        'tool_name': 'Read',
      });
      expect(old.source, 'builtin');
      final block = AiToolCallBlock(
        id: 'x',
        callId: 'call',
        toolName: 'mcp__notes__write',
        arguments: const {},
        metadata: const {
          'tool_source': 'mcp',
          'mcp_server': 'notes',
          'mcp_tool': 'write',
        },
        result: const {'ok': true, 'executionState': 'succeeded'},
      );
      final restored = AiToolCallBlock.fromJson(
        jsonDecode(jsonEncode(block.toJson())) as Map<String, dynamic>,
      );
      expect(restored.source, 'mcp');
      expect(restored.mcpServer, 'notes');
      expect(restored.executionState, 'succeeded');
      expect(restored.hasDiff, false);
    },
  );
}
