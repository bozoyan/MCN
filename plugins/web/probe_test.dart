// 职责: 用真实 fjs 验证正式 Web 插件产物与宿主 HTTP 桥接。
// 关联文件:
//   plugins/web/src/index.ts
//   assets/plugins/reveric.web/dist/index.js
//   lib/shared/services/plugins/runtime.dart
import 'dart:convert';
import 'dart:io';

import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/plugin/manifest.dart';
import 'package:reveric/shared/services/plugins/runtime.dart';

void main() {
  setUpAll(() async {
    final library = Platform.environment['FJS_PROBE_LIBRARY'];
    if (library == null) {
      throw StateError('Set FJS_PROBE_LIBRARY to the built native FJS library');
    }
    await LibFjs.init(externalLibrary: ExternalLibrary.open(library));
  });

  test('committed manifest matches source and bundle stays within budget', () {
    expect(
      File('assets/plugins/reveric.web/plugin.json').readAsStringSync(),
      File('plugins/web/plugin.json').readAsStringSync(),
    );
    expect(
      File('assets/plugins/reveric.web/dist/index.js').lengthSync(),
      lessThanOrEqualTo(2 * 1024 * 1024),
    );
  });

  test(
    'formal bundle activates and executes both tools in fresh fjs runtimes',
    () async {
      final manifest = PluginManifest.fromJson(
        jsonDecode(
              File('assets/plugins/reveric.web/plugin.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final code = File(
        'assets/plugins/reveric.web/dist/index.js',
      ).readAsStringSync();
      final requests = <String>[];
      PluginRuntime runtime() => PluginRuntime(
        hostCall: (method, args) async {
          if (method.startsWith('log.')) {
            return null;
          }
          expect(method, 'http.fetch');
          final url = args['url'] as String;
          requests.add(url);
          if (url.endsWith('/error')) {
            throw PluginHostError('network', 'DNS lookup failed: ENOTFOUND');
          }
          if (url.startsWith('https://www.baidu.com/s?')) {
            return {
              'status': 200,
              'url': url,
              'headers': {'content-type': 'text/html'},
              'body':
                  '<html><head><script>location.replace(location.href.replace("https://", "http://"));</script></head><body><noscript><meta http-equiv="refresh" content="0;url=http://www.baidu.com/"></noscript></body></html>',
            };
          }
          return {
            'status': 200,
            'url': url,
            'headers': {'content-type': 'text/html; charset=utf-8'},
            'body': url.contains('baidu.com')
                ? '<html><div class="result c-container"><h3><a href="https://example.com">中文结果</a></h3><p>搜索摘要</p><script>tracking()</script><style>.hidden{display:none}</style></div></html>'
                : '<html><head><title>示例</title><base href="/assets/"></head><body><h1>中文标题</h1><p>Hello <strong>world</strong></p><img alt="chart" src="chart.png"><script>secret()</script></body></html>',
          };
        },
      );
      final watch = Stopwatch()..start();
      final definitions = await runtime().activate(manifest, code);
      stdout.writeln(
        'activation_ms=${watch.elapsedMilliseconds} bundle_bytes=${utf8.encode(code).length}',
      );
      expect(definitions.map((d) => d['name']), ['WebSearch', 'WebFetch']);
      final search = await runtime().invoke(
        manifest,
        code,
        definitions,
        'WebSearch',
        {'query': 'test'},
        'search',
        null,
      );
      expect(search['engine'], 'baidu');
      expect(search['results'], hasLength(1));
      expect((search['results'] as List).single['title'], '中文结果');
      expect((search['results'] as List).single['snippet'], '搜索摘要');
      expect(requests.take(2), [
        'https://www.baidu.com/s?wd=test',
        'http://www.baidu.com/s?wd=test',
      ]);
      final fetch = await runtime().invoke(
        manifest,
        code,
        definitions,
        'WebFetch',
        {'url': 'https://example.com'},
        'fetch',
        null,
      );
      expect(fetch['title'], '示例');
      expect(fetch['content'], contains('# 中文标题'));
      expect(fetch['content'], contains('**world**'));
      expect(
        fetch['content'],
        contains('https://example.com/assets/chart.png'),
      );
      expect(fetch['content'], isNot(contains('secret()')));
      expect(fetch['format'], 'markdown');
      final failure = await runtime().invoke(
        manifest,
        code,
        definitions,
        'WebFetch',
        {'url': 'https://example.com/error'},
        'error',
        null,
      );
      expect(failure['failure_kind'], 'network');
      expect((failure['diagnostic'] as Map)['error'], contains('ENOTFOUND'));
      expect(failure['error'], isNot(contains('ENOTFOUND')));
      expect(requests, hasLength(4));
    },
  );
}
