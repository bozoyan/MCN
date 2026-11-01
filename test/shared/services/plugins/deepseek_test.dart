// 职责: 用打包产物和真实 QuickJS 验证 DeepSeek 插件注册、凭据桥接、搜索和抓取调用及 API Key 验证操作。
// 关联文件:
//   lib/shared/services/plugins/runtime.dart
//   lib/shared/services/plugins/host.dart
//   lib/shared/services/plugins/prelude.dart
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' hide PluginRegistry;
import 'package:reveric/shared/models/plugin/manifest.dart';
import 'package:reveric/shared/services/plugins/host.dart';
import 'package:reveric/shared/services/plugins/registry.dart';
import 'package:reveric/shared/services/plugins/runtime.dart';

void main() {
  setUpAll(() async {
    final path = Platform.environment['FJS_PROBE_LIBRARY'];
    if (path == null) {
      throw StateError('Set FJS_PROBE_LIBRARY to built native fjs');
    }
    await LibFjs.init(externalLibrary: ExternalLibrary.open(path));
  });
  test(
    'bundled DeepSeek tools coexist with web and read saved API key on each call',
    () async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final requests = <Map<String, dynamic>>[];
      final host = PluginHostService(
        dao: db.pluginDao,
        registry: PluginRegistry(hostToolNames: {}),
        packages: () async => [
          for (final id in ['reveric.web', 'reveric.deepseek'])
            PluginPackage(
              'assets/plugins/$id',
              PluginManifest.fromJson(
                jsonDecode(
                      File('assets/plugins/$id/plugin.json').readAsStringSync(),
                    )
                    as Map<String, dynamic>,
              ),
              File('assets/plugins/$id/dist/index.js').readAsStringSync(),
            ),
        ],
        executorFactory: (call, stop) => PluginRuntime(
          hostCall: (method, args) async {
            if (method != 'http.fetch') {
              return call(method, args);
            }
            requests.add(args);
            return {
              'status':
                  (args['headers'] as Map)['Authorization'] == 'Bearer bad-key'
                  ? 401
                  : 200,
              'url': args['url'],
              'headers': <String, String>{},
              'body': jsonEncode(
                (args['url'] as String).endsWith('/search')
                    ? {
                        'results': [
                          {
                            'title': 'Found',
                            'url': 'https://example.com',
                            'snippet': '中文摘要',
                            'summary': 'Full summary',
                            'content': '',
                            'date': null,
                            'authority': 3,
                            'rerank_score': 2.4,
                          },
                        ],
                      }
                    : {'title': 'Article', 'content': '# Markdown\n\n中文正文'},
              ),
            };
          },
          onStop: stop,
        ),
        platform: 'macos',
      );
      addTearDown(() async {
        await host.dispose();
        await db.close();
      });
      await host.start();
      expect(
        host.registry.effectiveTools.map((t) => t.name),
        containsAll(['WebSearch', 'WebFetch']),
      );
      expect(host.registry.resolve('DeepSeekSearch'), null);
      // 设置页验证在插件关闭时也可执行，并使用表单中未保存的 Key。
      expect(
        await host.runAction(
          'reveric.deepseek',
          'verifyApiKey',
          secrets: {'apiKey': 'draft-key'},
        ),
        (ok: true, code: null),
      );
      expect(requests.single['url'], 'https://api.deepseek.com/models');
      expect(requests.single['method'], 'GET');
      expect(requests.single['headers']['Authorization'], 'Bearer draft-key');
      expect(
        await host.runAction(
          'reveric.deepseek',
          'verifyApiKey',
          secrets: {'apiKey': 'bad-key'},
        ),
        (ok: false, code: 'unauthorized'),
      );
      expect(await db.pluginDao.secretValues('reveric.deepseek'), isEmpty);
      requests.clear();
      await host.saveConfig(
        'reveric.deepseek',
        settings: {},
        secrets: {'apiKey': 'first-key'},
      );
      await host.setEnabled('reveric.deepseek', true);
      expect(
        host.registry.effectiveTools.map((t) => t.name),
        containsAll([
          'WebSearch',
          'WebFetch',
          'DeepSeekSearch',
          'DeepSeekFetch',
        ]),
      );
      final result = await host.execute('DeepSeekSearch', {
        'query': '中文 search',
        'count': 50,
        'need_content': true,
      });
      expect(result['ok'], true);
      expect((result['results'] as List).single['summary'], 'Full summary');
      expect(
        requests.single['url'],
        'https://api.deepseek.com/v1/tools/search',
      );
      expect(requests.single['headers']['Authorization'], 'Bearer first-key');
      expect(jsonDecode(requests.single['body'] as String), {
        'query': '中文 search',
        'count': 50,
        'need_content': true,
      });
      await host.saveConfig(
        'reveric.deepseek',
        settings: {},
        secrets: {'apiKey': 'second-key'},
      );
      final fetched = await host.execute('DeepSeekFetch', {
        'url': 'https://example.com',
      });
      expect(fetched, {
        'ok': true,
        'title': 'Article',
        'content': '# Markdown\n\n中文正文',
      });
      expect(requests.last['headers']['Authorization'], 'Bearer second-key');
      await host.setEnabled('reveric.deepseek', false);
      expect(host.registry.resolve('DeepSeekSearch'), null);
      expect(host.registry.resolve('WebSearch'), isNotNull);
    },
  );
}
