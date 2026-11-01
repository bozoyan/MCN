// 职责: LoopDetector 单元测试 — 验证连续重复检测与状态推进检测的判定边界
// 关联文件:
//   lib/shared/agent/loop_detector.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/loop_detector.dart';
import 'package:reveric/shared/agent/message.dart';

ToolCall _call(String name, [Map<String, dynamic>? args]) {
  return ToolCall(
    callId: 'call_$name',
    toolName: name,
    arguments: args ?? const {},
  );
}

void main() {
  group('LoopDetector Layer 1 — consecutive identical', () {
    test('3 consecutive identical calls → hint severity', () {
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/a'}));

      final result = d.check();
      expect(result, isNotNull);
      expect(result!.severity, LoopSeverity.hint);
      expect(result.details['consecutiveCount'], 3);
    });

    test('5 consecutive identical calls → abort severity', () {
      final d = LoopDetector();
      for (var i = 0; i < 5; i++) {
        d.recordToolCall(_call('Read', {'path': '/a'}));
      }

      final result = d.check();
      expect(result, isNotNull);
      expect(result!.severity, LoopSeverity.abort);
      expect(result.details['consecutiveCount'], 5);
    });

    test('scattered identical calls (not consecutive) → no loop', () {
      // 旧逻辑：窗口内频次 3 就判定。新逻辑要求连续才判定。
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'})); // A
      d.recordToolCall(_call('Write', {'path': '/b'})); // B
      d.recordToolCall(_call('Read', {'path': '/a'})); // A — 散落，非连续
      d.recordToolCall(_call('Grep', {'pattern': 'x'})); // C
      d.recordToolCall(_call('Read', {'path': '/a'})); // A — 散落，非连续

      final result = d.check();
      expect(result, isNull, reason: '散落的重复调用不应被判为循环');
    });

    test('2 consecutive then different → no loop', () {
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/b'})); // 参数变了，非连续

      expect(d.check(), isNull);
    });

    test('different arguments on same tool → not identical', () {
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/b'}));
      d.recordToolCall(_call('Read', {'path': '/c'}));

      expect(d.check(), isNull);
    });

    test('fewer than hintThreshold calls → no loop', () {
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/a'}));

      expect(d.check(), isNull);
    });
  });

  group('LoopDetector Layer 2 — state progression', () {
    test('5 rounds with identical signature → abort', () {
      final d = LoopDetector();
      for (var i = 0; i < 5; i++) {
        d.recordRound('same text', [
          _call('Read', {'path': '/a'}),
        ], resultDigest: 'ok');
      }

      final result = d.check();
      expect(result, isNotNull);
      expect(result!.severity, LoopSeverity.abort);
      expect(result.reason, contains('State oscillation'));
    });

    test('text progression breaks oscillation', () {
      final d = LoopDetector();
      d.recordRound('thinking 1', [
        _call('Read', {'path': '/a'}),
      ]);
      d.recordRound('thinking 2', [
        _call('Read', {'path': '/a'}),
      ]);
      d.recordRound('thinking 3', [
        _call('Read', {'path': '/a'}),
      ]);
      d.recordRound('thinking 4', [
        _call('Read', {'path': '/a'}),
      ]);
      d.recordRound('thinking 5', [
        _call('Read', {'path': '/a'}),
      ]);

      // 文本在推进 → 签名不同 → 不算振荡
      expect(d.check(), isNull);
    });

    test('different result digest breaks oscillation', () {
      final d = LoopDetector();
      d.recordRound('same', [
        _call('Search', {'q': 'x'}),
      ], resultDigest: 'ok:3');
      d.recordRound('same', [
        _call('Search', {'q': 'x'}),
      ], resultDigest: 'ok:5');
      d.recordRound('same', [
        _call('Search', {'q': 'x'}),
      ], resultDigest: 'ok:7');
      d.recordRound('same', [
        _call('Search', {'q': 'x'}),
      ], resultDigest: 'ok:9');
      d.recordRound('same', [
        _call('Search', {'q': 'x'}),
      ], resultDigest: 'ok:11');

      // 结果在变化 → 签名不同 → 不算振荡
      expect(d.check(), isNull);
    });

    test('fewer than stateWindowSize rounds → no oscillation', () {
      final d = LoopDetector();
      for (var i = 0; i < 4; i++) {
        d.recordRound('same', [
          _call('Read', {'path': '/a'}),
        ]);
      }
      expect(d.check(), isNull);
    });
  });

  group('LoopDetector markHintInjected', () {
    test('markHintInjected sets flag', () {
      final d = LoopDetector();
      expect(d.hintInjected, isFalse);
      d.markHintInjected();
      expect(d.hintInjected, isTrue);
    });
  });

  group('LoopDetector hint scoping — 不同循环各自获得 hint', () {
    ToolCall read() => _call('Read', {'path': '/a'});
    ToolCall grep() => _call('Grep', {'q': 'x'});

    test('换了 call 的新循环获得自己的 hint，而非被上一个循环连坐 abort', () {
      final d = LoopDetector();
      // 循环 1：Read ×3 → hint，模拟 agent 注入提示。
      d.recordToolCall(read());
      d.recordToolCall(read());
      d.recordToolCall(read());
      expect(d.check()!.severity, LoopSeverity.hint);
      d.markHintInjected();

      // 模型改用别的工具（未出现空 tool 轮，不触发 resetConsecutive）。
      // 换 call 应清除上一个循环的 hint 标记。
      d.recordToolCall(grep());
      d.recordToolCall(grep());
      d.recordToolCall(grep());

      final result = d.check();
      expect(result, isNotNull);
      expect(
        result!.severity,
        LoopSeverity.hint,
        reason: '不同的循环应各自获得一次 hint 机会，不能被上一个循环的提示状态连坐',
      );
      expect(d.hintInjected, isFalse, reason: '换 call 后上一个循环的 hint 标记应已失效');
    });

    test('同一个 call 在 hint 后继续重复 → hint 标记保持（供 agent 升级为 abort）', () {
      final d = LoopDetector();
      d.recordToolCall(read());
      d.recordToolCall(read());
      d.recordToolCall(read());
      expect(d.check()!.severity, LoopSeverity.hint);
      d.markHintInjected();

      // 同一个 call 继续重复，不清除标记。
      d.recordToolCall(read());
      expect(
        d.hintInjected,
        isTrue,
        reason: '同一个循环重复应保留 hint 标记，由 agent 层结合它升级为 abort',
      );
    });
  });

  group('LoopDetector reset', () {
    test('reset clears all history and flags', () {
      final d = LoopDetector();
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordRound('text', [
        _call('Read', {'path': '/a'}),
      ]);
      d.markHintInjected();

      d.reset();

      expect(d.check(), isNull);
      expect(d.hintInjected, isFalse);
    });
  });

  group('LoopDetector custom config', () {
    test('custom thresholds are respected', () {
      final d = LoopDetector(
        config: const LoopDetectorConfig(hintThreshold: 2, abortThreshold: 4),
      );
      d.recordToolCall(_call('Read', {'path': '/a'}));
      d.recordToolCall(_call('Read', {'path': '/a'}));

      final result = d.check();
      expect(result, isNotNull);
      expect(result!.severity, LoopSeverity.hint);
    });
  });
}
