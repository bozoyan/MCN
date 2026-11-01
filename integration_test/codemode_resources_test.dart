// 职责: 在真实原生 runtime 验证剩余预算、连续回收与驻留内存趋势。
// 关联文件:
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/services/ai/codemode/scheduler.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';

const _read = ToolDef(
  name: 'Read',
  description: 'Fixture',
  inputSchema: {'type': 'object'},
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native heap stack input and aggregate result limits recover', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final scenario in <(String, CodemodeRuntimeLimits, String)>[
        (
          'const values=[]; while(true) values.push(new Array(10000).fill(42));',
          const CodemodeRuntimeLimits(heapBytes: 2 * 1024 * 1024),
          'codemode_memory_limit',
        ),
        (
          'function recurse(){return 1 + recurse();} recurse();',
          const CodemodeRuntimeLimits(stackBytes: 64 * 1024),
          'codemode_resource_limit',
        ),
        (
          'await tools.Read({value:"x".repeat(1024)});',
          const CodemodeRuntimeLimits(inputBytes: 64),
          'codemode_resource_limit',
        ),
      ]) {
        final runtime = FjsRuntime();
        final result = await runtime.run(
          code: scenario.$1,
          tools: [_read],
          executeTool: (_, _) async => {'ok': true, 'text': 'fixture-data'},
          limits: scenario.$2,
        );
        expect(result.errorCode, scenario.$3, reason: scenario.$1);
        await runtime.settled.timeout(const Duration(seconds: 1));
        final healthy = await FjsRuntime().run(
          code: 'return 42;',
          tools: const [],
          executeTool: (_, _) async => {},
        );
        expect(healthy.returnValue, 42);
      }
    });
  });

  testWidgets(
    '100 native create execute close cycles settle without retained requests',
    (tester) async {
      await tester.runAsync(() async {
        var pending = 0;
        final samples = <int>[];
        for (var i = 0; i < 100; i++) {
          final runtime = FjsRuntime();
          final result = await runtime.run(
            code:
                'const value=await tools.Read({}); text(value.text); return 42;',
            tools: [_read],
            executeTool: (_, _) async {
              pending++;
              try {
                return {'ok': true, 'text': 'memory fixture 中文'};
              } finally {
                pending--;
              }
            },
          );
          expect(result.returnValue, 42);
          expect(result.output, ['memory fixture 中文']);
          await runtime.settled.timeout(const Duration(seconds: 1));
          expect(pending, 0);
          // close() has no native deallocation signal; sample after its executor
          // can release idle allocations, without closeGracefully draining jobs.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          samples.add(ProcessInfo.currentRss);
        }
        debugPrintSynchronously('CODEMODE_RSS_BYTES=${jsonEncode(samples)}');
        double mean(Iterable<int> data) =>
            data.reduce((a, b) => a + b) / data.length;
        final early = mean(samples.skip(20).take(20));
        final late = mean(samples.skip(80));
        debugPrintSynchronously(
          'CODEMODE_RSS_WARM_MEAN=$early FINAL_MEAN=$late DELTA=${late - early}',
        );
        // Permit allocator/Flutter noise while catching a retained runtime per run.
        expect(late - early, lessThan(16 * 1024 * 1024));
      });
    },
  );
}
