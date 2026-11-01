// 职责: 测试 session trace headers 的构造 — 顶层会话与子会话的父子归属
// 关联文件:
//   lib/shared/agent/client/trace_headers_http_client.dart
//   lib/shared/services/ai/spawn_agent_handler.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/client/trace_headers_http_client.dart';

void main() {
  test('top-level session reports itself as its own parent', () {
    expect(
      buildTraceSessionHeaders(sessionId: 'ai_session_1', sessionMode: 'chat'),
      {
        'x-session-mode': 'chat',
        'x-session-id': 'ai_session_1',
        'x-session-parent-id': 'ai_session_1',
      },
    );
  });

  test('sub session reports the spawning session as parent', () {
    expect(
      buildTraceSessionHeaders(
        sessionId: 'sub_session_1',
        parentSessionId: 'ai_session_1',
        sessionMode: 'chat',
      ),
      {
        'x-session-mode': 'chat',
        'x-session-id': 'sub_session_1',
        'x-session-parent-id': 'ai_session_1',
      },
    );
  });

  test('empty parent falls back to the session itself', () {
    expect(
      buildTraceSessionHeaders(
        sessionId: 'ai_session_1',
        parentSessionId: '',
        sessionMode: 'theater',
      )['x-session-parent-id'],
      'ai_session_1',
    );
  });

  test('session headers are omitted when there is no session id', () {
    expect(buildTraceSessionHeaders(sessionMode: 'memory'), {
      'x-session-mode': 'memory',
    });
  });

  group('buildTraceSubSessionId', () {
    test('is stable per participant and distinct across participants', () {
      final first = buildTraceSubSessionId(
        parentSessionId: 'theater_1',
        participantId: 'character_a',
      );
      expect(
        first,
        buildTraceSubSessionId(
          parentSessionId: 'theater_1',
          participantId: 'character_a',
        ),
      );
      expect(
        first,
        isNot(
          buildTraceSubSessionId(
            parentSessionId: 'theater_1',
            participantId: 'character_b',
          ),
        ),
      );
      expect(
        first,
        isNot(
          buildTraceSubSessionId(
            parentSessionId: 'theater_2',
            participantId: 'character_a',
          ),
        ),
      );
    });

    test('returns empty when either side is missing', () {
      expect(
        buildTraceSubSessionId(parentSessionId: '', participantId: 'char'),
        isEmpty,
      );
      expect(
        buildTraceSubSessionId(parentSessionId: 'theater_1', participantId: ''),
        isEmpty,
      );
    });
  });
}
