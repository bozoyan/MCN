// 职责: 用真实 fjs 验证插件桥接、注册生命周期、错误和资源终止。
// 关联文件:
//   lib/shared/services/plugins/runtime.dart
import 'dart:async';
import 'dart:io';
import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/models/plugin/manifest.dart';
import 'package:reveric/shared/services/plugins/runtime.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';

final manifest = PluginManifest.fromJson({
  'id': 'test.plugin',
  'name': 'Test',
  'version': '1.0.0',
  'pluginApiVersion': '^1',
  'main': 'dist/index.js',
});
String plugin(String handler, {String apply = ''}) =>
    "var __revericPlugin={async apply(context){$apply context.tools.register({name:'Echo',description:'Echo input',inputSchema:{type:'object'},handler:async(input)=>{$handler}});}};";
void main() {
  setUpAll(() async {
    final path = Platform.environment['FJS_PROBE_LIBRARY'];
    if (path == null) {
      throw StateError('Set FJS_PROBE_LIBRARY to built native fjs');
    }
    await LibFjs.init(externalLibrary: ExternalLibrary.open(path));
  });
  PluginRuntime runtime({
    PluginHostCall? call,
    Duration timeout = const Duration(seconds: 60),
  }) => PluginRuntime(
    hostCall: call ?? (method, args) async => args,
    callTimeout: timeout,
  );
  test(
    'codemode and plugins share initialization without sharing execution',
    () async {
      final result = await FjsRuntime().run(
        code: 'return 7;',
        tools: [],
        executeTool: (name, input) async => {},
      );
      expect(result.ok, true);
      expect(result.returnValue, 7);
      expect(
        await runtime().activate(manifest, plugin('return {};')),
        hasLength(1),
      );
    },
  );
  test('fresh runtimes register, bridge promises and return JSON', () async {
    final code = plugin(
      "return await context.http.fetch('https://example.com');",
    );
    final definitions = await runtime().activate(manifest, code);
    expect(definitions.single['name'], 'Echo');
    final result = await runtime(
      call: (m, a) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return {'body': '中文'};
      },
    ).invoke(manifest, code, definitions, 'Echo', {}, 'call', null);
    expect(result, {'body': '中文'});
  });
  test('apply Host calls and registration after apply fail', () async {
    await expectLater(
      runtime().activate(
        manifest,
        plugin(
          'return {};',
          apply: "await context.http.fetch('https://example.com');",
        ),
      ),
      throwsA(isA<PluginExecutionError>()),
    );
    final code = plugin("context.tools.register({name:'Late'}); return {};");
    final defs = await runtime().activate(manifest, code);
    await expectLater(
      runtime().invoke(manifest, code, defs, 'Echo', {}, '', null),
      throwsA(isA<PluginExecutionError>()),
    );
  });
  test(
    'registration mismatch, thrown host errors and invalid result remain diagnostic',
    () async {
      final code = plugin('return {};');
      final defs = await runtime().activate(manifest, code);
      await expectLater(
        runtime().invoke(
          manifest,
          code,
          [
            {...defs.single, 'description': 'changed'},
          ],
          'Echo',
          {},
          '',
          null,
        ),
        throwsA(
          isA<PluginExecutionError>().having(
            (e) => e.code,
            'code',
            'plugin_registration_mismatch',
          ),
        ),
      );
      for (final handler in [
        'return 42;',
        "return {body:'x'.repeat(270000)};",
      ]) {
        final bad = plugin(handler);
        await expectLater(
          runtime().invoke(manifest, bad, defs, 'Echo', {}, '', null),
          throwsA(
            isA<PluginExecutionError>().having(
              (e) => e.code,
              'code',
              'plugin_invalid_result',
            ),
          ),
        );
      }
      final net = plugin(
        "return await context.http.fetch('https://example.com');",
      );
      await expectLater(
        runtime(
          call: (m, a) async =>
              throw PluginHostError('network', 'DNS unavailable'),
        ).invoke(manifest, net, defs, 'Echo', {}, '', null),
        throwsA(
          isA<PluginExecutionError>()
              .having((e) => e.hostCode, 'hostCode', 'network')
              .having((e) => e.message, 'message', contains('DNS unavailable')),
        ),
      );
    },
  );
  test(
    'timeout and cancellation close runtime; subsequent call succeeds',
    () async {
      final code = plugin('await new Promise(()=>{}); return {};');
      final defs = await runtime().activate(manifest, code);
      await expectLater(
        runtime(
          timeout: const Duration(milliseconds: 100),
        ).invoke(manifest, code, defs, 'Echo', {}, '', null),
        throwsA(
          isA<PluginExecutionError>().having(
            (e) => e.code,
            'code',
            'plugin_timeout',
          ),
        ),
      );
      final controller = AgentCancellationController();
      final future = runtime().invoke(
        manifest,
        code,
        defs,
        'Echo',
        {},
        '',
        controller.token,
      );
      Timer(const Duration(milliseconds: 100), controller.cancel);
      await expectLater(
        future,
        throwsA(
          isA<PluginExecutionError>().having(
            (e) => e.code,
            'code',
            'user_cancelled',
          ),
        ),
      );
      expect(
        await runtime().invoke(
          manifest,
          plugin('return {ok:true};'),
          defs,
          'Echo',
          {},
          '',
          null,
        ),
        {'ok': true},
      );
    },
  );
  test('memory exhaustion closes runtime', () async {
    final code = plugin(
      "const a=[]; while(true) {a.push(new Array(100000).fill('abcdefgh'));}",
    );
    final defs = await runtime().activate(manifest, code);
    await expectLater(
      runtime().invoke(manifest, code, defs, 'Echo', {}, '', null),
      throwsA(
        isA<PluginExecutionError>().having(
          (e) => e.code,
          'code',
          'plugin_memory_limit',
        ),
      ),
    );
  });
}
