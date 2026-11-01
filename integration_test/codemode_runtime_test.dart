// 职责: 用真实 FJS 验证 Codemode 脚本 API、JSON 边界、预算和取消收口。
// 关联文件:
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/services/ai/codemode/prelude.dart
//   lib/shared/agent/agent_tool_dispatcher.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';
import 'package:reveric/shared/services/ai/tool_error_normalize.dart';

const _read = ToolDef(
  name: 'Read',
  description: 'Read a local test record.',
  inputSchema: {'type': 'object'},
  outputSchema: {
    'type': 'object',
    'properties': {
      'ok': {'type': 'boolean'},
    },
    'required': ['ok'],
  },
);

Future<Map<String, dynamic>> _echo(
  String name,
  Map<String, dynamic> input,
) async => {'ok': true, 'input': input};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('script locals may shadow injected API names', (tester) async {
    await tester.runAsync(() async {
      final discoveries = <String>[];
      const catalog = {
        'tools': [
          {'name': 'mcp__search1api__search'},
        ],
      };
      final result = await FjsRuntime().run(
        code: '''
const tools = await listTools({ mcpServer: "search1api" });
text(tools);
''',
        tools: const [],
        executeTool: (_, _) async => throw StateError('No tool should execute'),
        discover: (method, input) async {
          discoveries.add(method);
          expect(input, {'mcpServer': 'search1api'});
          return catalog;
        },
      );
      expect(result.ok, isTrue, reason: '${result.toJson()}');
      expect(result.output, [catalog]);
      expect(result.hasReturn, isFalse);
      expect(result.callCount, 0);
      expect(discoveries, ['listTools']);

      for (final name in [
        'tools',
        'text',
        'listMcpServers',
        'listTools',
        'searchTool',
        'describeTool',
      ]) {
        for (final declaration in ['const', 'let', 'var']) {
          final shadowed = await FjsRuntime().run(
            code: '$declaration $name = "local"; return $name;',
            tools: const [],
            executeTool: _echo,
          );
          expect(
            shadowed.ok,
            isTrue,
            reason: '$declaration $name: ${shadowed.toJson()}',
          );
          expect(shadowed.returnValue, 'local');
        }
      }
      final strict = await FjsRuntime().run(
        code: '"use strict"; accidentalGlobal = 1;',
        tools: const [],
        executeTool: _echo,
      );
      expect(strict.errorCode, 'codemode_script_error');
      expect(strict.jsErrorMessage, startsWith('ReferenceError:'));
      final trailingComment = await FjsRuntime().run(
        code: 'return await tools.Read({value: 1}); // trailing comment',
        tools: [_read],
        executeTool: _echo,
      );
      expect(trailingComment.ok, isTrue);
      expect(trailingComment.returnValue, {
        'ok': true,
        'input': {'value': 1},
      });
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('reports concrete JavaScript diagnostics from real FJS', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final (code, type) in [
        ('const value = ;', 'SyntaxError'),
        ('return missingName;', 'ReferenceError'),
        ('return undefined.content;', 'TypeError'),
        ('throw new Error("example failure");', 'Error'),
      ]) {
        final result = await FjsRuntime().run(
          code: code,
          tools: const [],
          executeTool: _echo,
        );
        expect(result.errorCode, 'codemode_script_error');
        final payload = result.toJson();
        final reported = codemodeAnonymousFailure(payload, {'code': code});
        expect(reported['exception_message'], startsWith('$type:'));
        expect(reported['exception_message'], isNot(contains('\n')));
        expect(payload['error'], codemodeErrorMessage('codemode_script_error'));
        if (type == 'ReferenceError') {
          expect(reported['exception_message'], contains('missingName'));
        }
      }
    });
  });
  testWidgets('script sees public tool recovery fields', (tester) async {
    await tester.runAsync(() async {
      const recovery = {
        'tool': 'Read',
        'input': {'path': 'chapters/test/content'},
      };
      final runtime = FjsRuntime();
      final result = await runtime.run(
        code: '''
try {
  await tools.Read({path: 'chapters/test/content'});
} catch (error) {
  return {
    message: error.message, error_code: error.error_code,
    error: error.error, hint: error.hint, recovery: error.recovery,
    hasMetadata: Object.hasOwn(error, '_metadata'),
    hasHostDetails: Object.hasOwn(error, 'host_details')
  };
}
''',
        tools: [_read],
        executeTool: (_, _) async => {
          'ok': false,
          'error_code': 'old_text_not_found',
          'error': 'The original text does not match.',
          'hint': 'Read the field and copy the original text exactly.',
          'recovery': recovery,
          '_metadata': {'private': 'UI only'},
          'host_details': 'PRIVATE HOST PATH',
        },
      );
      expect(result.errorCode, isNull);
      expect(result.failedCount, 1);
      expect(result.returnValue, {
        'message': 'old_text_not_found',
        'error_code': 'old_text_not_found',
        'error': 'The original text does not match.',
        'hint': 'Read the field and copy the original text exactly.',
        'recovery': recovery,
        'hasMetadata': false,
        'hasHostDetails': false,
      });
      await runtime.settled;

      Future<Map<String, dynamic>> fail(
        String name,
        Map<String, dynamic> input,
      ) async => {
        'ok': false,
        'error_code': 'old_text_not_found',
        'error': 'The original text does not match.',
        'hint': 'Read the field again.',
        'recovery': recovery,
      };
      for (final code in [
        'text("partial"); await tools.Read({});',
        'text("partial"); try { await tools.Read({}); } catch (error) { error.hint = "MUTATED"; throw error; }',
      ]) {
        final uncaught = await FjsRuntime().run(
          code: code,
          tools: [_read],
          executeTool: fail,
        );
        expect(uncaught.errorCode, 'codemode_script_error');
        expect(uncaught.output, ['partial']);
        expect(uncaught.toJson()['tool_error'], {
          'tool': 'Read',
          'ok': false,
          'error_code': 'old_text_not_found',
          'error': 'The original text does not match.',
          'hint': 'Read the field again.',
          'recovery': recovery,
        });
      }
      final unrelated = await FjsRuntime().run(
        code:
            'try { await tools.Read({}); } catch (_) {} throw new Error("PRIVATE");',
        tools: [_read],
        executeTool: fail,
      );
      expect(unrelated.errorCode, 'codemode_script_error');
      expect(unrelated.toolError, isNull);
      expect(unrelated.toJson()['error'], isNot(contains('PRIVATE')));
      expect(unrelated.jsErrorMessage, 'Error: PRIVATE');
    });
  });

  testWidgets('real Codemode API, JSON and output envelope', (tester) async {
    await tester.runAsync(() async {
      final runtime = FjsRuntime();
      final result = await runtime.run(
        code: '''
const input = JSON.parse('{"__proto__":{"secret":42},"constructor":"data","id":"9007199254740993","text":"中文 😀","items":[null,true,2]}');
const result = await tools.Read(input);
text(result.input);
return {value: result.input};
''',
        tools: [_read],
        executeTool: _echo,
      );
      expect(result.errorCode, isNull);
      expect(result.completedCount, 1);
      expect(result.output.length, 1);
      final input = result.output.first as Map;
      expect(input['id'], '9007199254740993');
      expect(input['text'], '中文 😀');
      expect(input['__proto__'], {'secret': 42});
      expect((result.returnValue as Map)['value'], input);
      await runtime.settled;

      final compute = await FjsRuntime().run(
        code: 'return [1, 2, 3].reduce((a, b) => a + b, 0);',
        tools: const [],
        executeTool: _echo,
      );
      expect(compute.returnValue, 6);
      expect(compute.callCount, 0);
      final failed = await FjsRuntime().run(
        code: 'text("saved"); throw new Error("PRIVATE HOST PATH");',
        tools: const [],
        executeTool: _echo,
      );
      expect(failed.errorCode, 'codemode_script_error');
      expect(failed.output, ['saved']);
      expect(failed.toJson()['error'], isNot(contains('PRIVATE HOST PATH')));
      expect(failed.jsErrorMessage, 'Error: PRIVATE HOST PATH');
      final syntax = await FjsRuntime().run(
        code: '}); return "escaped"; //',
        tools: const [],
        executeTool: _echo,
      );
      expect(syntax.errorCode, 'codemode_script_error');
    });
  });

  testWidgets('undefined does not discard successful batch reads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final result = await FjsRuntime().run(
        code: r'''
const out = [];
for (let i = 0; i < 7; i++) {
  await tools.Read({path: 'scenes/' + i + '/elements'});
  const d = await tools.Read({path: 'scenes/' + i});
  out.push({id: i, title: d.title, cast: d.cast});
}
text(out);
text(undefined);
return out;
''',
        tools: [_read],
        executeTool: (_, input) async {
          return {'ok': true, 'title': '场次'};
        },
      );
      final expected = [
        for (var i = 0; i < 7; i++) {'id': i, 'title': '场次'},
      ];
      expect(result.errorCode, isNull, reason: '${result.toJson()}');
      expect(result.completedCount, 14);
      expect(result.failedCount, 0);
      expect(result.returnValue, expected);
      expect(result.output, [expected, 'undefined']);
    });
  });

  testWidgets(
    'native JSON semantics apply to input, output and return values',
    (tester) async {
      await tester.runAsync(() async {
        final result = await FjsRuntime().run(
          code: r'''
const value = {
  omitted: undefined,
  array: [undefined, , NaN, Infinity, () => 1, Symbol('x')],
  get accessor() { return 7; },
  custom: {toJSON() {return {kept: true, omitted: undefined};}}
};
const reply = await tools.Read(value);
text(value);
return reply.input;
''',
          tools: [_read],
          executeTool: _echo,
        );
        final expected = {
          'array': [null, null, null, null, null, null],
          'accessor': 7,
          'custom': {'kept': true},
        };
        expect(result.errorCode, isNull);
        expect(result.returnValue, expected);
        expect(result.output, [expected]);
        for (final code in [
          'return undefined;',
          'return () => 1;',
          'return Symbol("x");',
        ]) {
          final empty = await FjsRuntime().run(
            code: code,
            tools: const [],
            executeTool: _echo,
          );
          expect(empty.ok, isTrue, reason: code);
          expect(empty.hasReturn, isFalse, reason: code);
          expect(empty.output, isEmpty, reason: code);
        }
      });
    },
  );

  testWidgets('cycles fail but repeated references serialize normally', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repeated = await FjsRuntime().run(
        code: 'const a={x:1}; return [a,a];',
        tools: const [],
        executeTool: _echo,
      );
      expect(repeated.ok, isTrue);
      expect(repeated.returnValue, [
        {'x': 1},
        {'x': 1},
      ]);
      for (final (operation, stage) in [
        ('text(a);', 'output'),
        ('return a;', 'return_value'),
        ('await tools.Read(a);', 'tool_input'),
      ]) {
        final cycle = await FjsRuntime().run(
          code: 'text("saved"); const a={}; a.self=a; $operation',
          tools: [_read],
          executeTool: _echo,
        );
        expect(cycle.errorCode, 'codemode_invalid_input', reason: stage);
        expect(cycle.diagnostics['failure_stage'], stage);
        expect(cycle.output, ['saved']);
        expect(cycle.callCount, 0);
      }
      for (final argument in ['undefined', 'null', '[]', '1']) {
        final invalid = await FjsRuntime().run(
          code: 'await tools.Read($argument);',
          tools: [_read],
          executeTool: _echo,
        );
        expect(invalid.errorCode, 'codemode_invalid_input', reason: argument);
        expect(invalid.completedCount, 0);
      }
    });
  });

  testWidgets('invalid JSON and raw bridge cannot bypass host authority', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var executed = 0;
      Future<Map<String, dynamic>> execute(
        String name,
        Map<String, dynamic> input,
      ) async {
        executed++;
        return {'ok': true};
      }

      for (final code in [
        'const value = {}; value.self = value; text(value);',
        'text(1n);',
      ]) {
        final result = await FjsRuntime().run(
          code: code,
          tools: [_read],
          executeTool: execute,
        );
        expect(result.errorCode, 'codemode_invalid_input', reason: code);
      }
      for (final code in [
        'try { await tools.WebFetch({}); } catch (_) {} await tools.Read({});',
        '''await fjs.bridge_call(JSON.stringify({kind:"tool",tool:"Read",input:"{}",sessionId:"other"}));''',
        '''await fjs.bridge_call(JSON.stringify({kind:"tool",tool:"WebFetch",input:"{}"}));''',
      ]) {
        final result = await FjsRuntime().run(
          code: code,
          tools: [_read],
          executeTool: execute,
        );
        expect(result.errorCode, 'codemode_tool_forbidden', reason: code);
      }
      expect(executed, 0);
    });
  });

  testWidgets('host budgets stop execution and preserve accepted output', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final output = await FjsRuntime().run(
        code: 'text("first"); text("second"); return 42;',
        tools: const [],
        executeTool: _echo,
        limits: const CodemodeRuntimeLimits(outputFrames: 1),
      );
      expect(output.output, ['first']);
      expect(output.errorCode, 'codemode_resource_limit');
      final combined = await FjsRuntime().run(
        code: 'text("1234"); return "5678";',
        tools: const [],
        executeTool: _echo,
        limits: const CodemodeRuntimeLimits(outputBytes: 10),
      );
      expect(combined.errorCode, 'codemode_resource_limit');
    });
  });

  testWidgets('raised output budget and precise limit diagnostics', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final accepted = await FjsRuntime().run(
        code: 'for(let i=0;i<300;i++) text(i); return "x".repeat(40 * 1024);',
        tools: const [],
        executeTool: _echo,
      );
      expect(accepted.ok, isTrue);
      expect((accepted.returnValue as String).length, 40 * 1024);
      expect(accepted.output, hasLength(300));
      final cases = [
        (
          'text("x".repeat(20));',
          const CodemodeRuntimeLimits(outputBytes: 10),
          'output',
          'output_bytes',
          22,
          10,
        ),
        (
          'return "x".repeat(20);',
          const CodemodeRuntimeLimits(outputBytes: 10),
          'return_value',
          'output_bytes',
          22,
          10,
        ),
        (
          'text("1234"); return "5678";',
          const CodemodeRuntimeLimits(outputBytes: 10),
          'return_value',
          'output_bytes',
          12,
          10,
        ),
        (
          'text(1); text(2);',
          const CodemodeRuntimeLimits(outputFrames: 1),
          'output',
          'output_frames',
          2,
          1,
        ),
        (
          'await tools.Read({value:"x".repeat(20)});',
          const CodemodeRuntimeLimits(inputBytes: 10),
          'tool_input',
          'input_bytes',
          32,
          10,
        ),
      ];
      for (final (code, limits, stage, reason, observed, limit) in cases) {
        final result = await FjsRuntime().run(
          code: code,
          tools: [_read],
          executeTool: _echo,
          limits: limits,
        );
        expect(result.errorCode, 'codemode_resource_limit');
        expect(result.diagnostics['failure_stage'], stage);
        expect(result.diagnostics['failure_reason'], reason);
        expect(result.diagnostics['observed'], observed);
        expect(result.diagnostics['limit'], limit);
      }
      // Very deep trees overflow native stringify before the depth walk.
      for (final (levels, operation, stage) in [
        (66, 'return v;', 'return_value'),
        (5000, 'return v;', 'return_value'),
        (5000, 'text(v);', 'output'),
      ]) {
        final depth = await FjsRuntime().run(
          code: 'let v = {}; for(let i=0;i<$levels;i++) v={v}; $operation',
          tools: const [],
          executeTool: _echo,
        );
        expect(depth.errorCode, 'codemode_resource_limit', reason: '$levels');
        expect(depth.diagnostics['failure_reason'], 'json_depth');
        expect(depth.diagnostics['failure_stage'], stage);
      }
      final undefined = await FjsRuntime().run(
        code: 'text(undefined);',
        tools: const [],
        executeTool: _echo,
      );
      expect(undefined.ok, isTrue);
      expect(undefined.output, ['undefined']);
    });
  });

  testWidgets('deadline and cancellation settle eval and close', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final code in ['while (true) {}', 'await new Promise(() => {});']) {
        final runtime = FjsRuntime();
        final result = await runtime
            .run(
              code: code,
              tools: const [],
              executeTool: _echo,
              limits: const CodemodeRuntimeLimits(
                executionTime: Duration(milliseconds: 100),
              ),
            )
            .timeout(const Duration(seconds: 2));
        expect(result.errorCode, 'codemode_timeout');
        expect(result.diagnostics['failure_reason'], 'execution_time');
        expect(result.diagnostics['limit'], 100);
        expect(result.diagnostics['observed'], greaterThanOrEqualTo(100));
        await runtime.settled;
      }
      final controller = AgentCancellationController();
      final runtime = FjsRuntime();
      final future = runtime.run(
        code:
            'await (async () => {while (true) {await Promise.resolve();}})();',
        tools: const [],
        executeTool: _echo,
        cancellationToken: controller.token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      controller.cancel();
      expect(
        (await future.timeout(const Duration(seconds: 1))).errorCode,
        'user_cancelled',
      );
      await runtime.settled;
    });
  });
}
