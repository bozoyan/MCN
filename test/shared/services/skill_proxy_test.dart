// 职责: 用本地代理验证技能 HTTP 客户端路由、认证和代理设置即时读取。
// 关联文件:
//   lib/shared/services/proxy_client.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/providers/settings_providers.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socks5_proxy/socks_server.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/network_proxy.dart';
import 'package:reveric/shared/providers/agent_skill_catalog_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/proxy_client.dart';

class _Settings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings.defaults(),
  );
  void changeProxy(NetworkProxy proxy) {
    state = AsyncData(state.requireValue.copyWith(networkProxy: proxy));
  }
}

void main() {
  test(
    'one retained skill factory reads changed HTTP proxy and credentials',
    () async {
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => first.close(force: true));
      addTearDown(() => second.close(force: true));
      final requests = <(int, String?)>[];
      for (final (index, server) in [first, second].indexed) {
        server.listen((request) async {
          requests.add((
            index,
            request.headers.value(HttpHeaders.proxyAuthorizationHeader),
          ));
          request.response.write('proxy $index');
          await request.response.close();
        });
      }
      final container = ProviderContainer(
        overrides: [appSettingsProvider.overrideWith(_Settings.new)],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);
      final settings =
          container.read(appSettingsProvider.notifier) as _Settings;
      final create = container.read(skillHttpClientFactoryProvider);
      for (final (index, server) in [first, second].indexed) {
        settings.changeProxy(
          NetworkProxy(
            mode: NetworkProxyMode.custom,
            url: 'http://127.0.0.1:${server.port}',
            username: 'test',
            password: 'pass$index',
          ),
        );
        final client = await create();
        try {
          final response = await client.get<String>(
            'http://skills.invalid/catalog.json',
          );
          expect(response.data, 'proxy $index');
        } finally {
          client.close(force: true);
        }
      }
      expect(requests, [
        (0, 'Basic ${base64Encode(utf8.encode('test:pass0'))}'),
        (1, 'Basic ${base64Encode(utf8.encode('test:pass1'))}'),
      ]);
    },
  );

  for (final mode in [NetworkProxyMode.direct, NetworkProxyMode.environment]) {
    test('Dio $mode reaches a local origin', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        request.response.write('origin');
        await request.response.close();
      });
      final client = createProxyDioClient(
        NetworkProxy(mode: mode),
        options: BaseOptions(connectTimeout: const Duration(seconds: 3)),
      );
      addTearDown(() => client.close(force: true));
      expect(
        (await client.get<String>(
          'http://127.0.0.1:${origin.port}/skill',
        )).data,
        'origin',
      );
    });
  }

  test(
    'Dio SOCKS5 authenticates and resolves repository host at proxy',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        request.response.write('archive');
        await request.response.close();
      });
      final credentials = <(String, String)>[];
      final hosts = <String>[];
      final proxy = SocksServer(
        authHandler: (username, password) {
          credentials.add((username, password));
          return username == 'test' && password == 'secret';
        },
        lookup: (host, {type = InternetAddressType.any}) async {
          hosts.add(host);
          return [InternetAddress.loopbackIPv4];
        },
      );
      proxy.connections.listen((connection) => connection.forward());
      await proxy.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.stop);
      final client = createProxyDioClient(
        NetworkProxy(
          mode: NetworkProxyMode.custom,
          url: 'socks5://127.0.0.1:${proxy.proxies.keys.single}',
          username: 'test',
          password: 'secret',
        ),
        options: BaseOptions(connectTimeout: const Duration(seconds: 3)),
      );
      addTearDown(() => client.close(force: true));
      expect(
        (await client.get<String>(
          'http://repository.invalid:${origin.port}/archive',
        )).data,
        'archive',
      );
      expect(hosts, contains('repository.invalid'));
      expect(credentials, [('test', 'secret')]);
    },
  );
}
