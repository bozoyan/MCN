// 职责: 按代理设置配置 HTTP 客户端，支持直连、环境变量与带可选认证的 HTTP/SOCKS5 代理。
// 关联文件:
//   lib/shared/models/network_proxy.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/services/depth/model_service.dart
//   lib/shared/services/update/sources/github_releases_source.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:socks5_proxy/socks_client.dart';
import '../models/network_proxy.dart';

Future<HttpClient> createProxyHttpClient(NetworkProxy config) async =>
    _createProxyHttpClient(config);

/// 每次操作独占的 Dio；底层客户端延迟创建，关闭未发请求的 Dio 也不会泄漏连接。
Dio createProxyDioClient(NetworkProxy config, {BaseOptions? options}) =>
    Dio(options)
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => _createProxyHttpClient(config),
      );

HttpClient _createProxyHttpClient(NetworkProxy config) {
  if (!config.isValid) {
    throw const FormatException('Invalid network proxy configuration');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  switch (config.mode) {
    case NetworkProxyMode.environment:
      // Preserve dart:io's HTTP_PROXY / HTTPS_PROXY / NO_PROXY behavior.
      break;
    case NetworkProxyMode.direct:
      client.findProxy = (_) => 'DIRECT';
    case NetworkProxyMode.custom:
      configureHttpClientProxy(
        client,
        NetworkProxy.parseAddress(config.url)!,
        username: config.username,
        password: config.password,
      );
  }
  return client;
}

/// 让 [client] 经 [proxy] 发出请求；`socks5` 走 SOCKS5，其余 scheme 按 HTTP 代理处理。
///
/// 用户名和密码须同时非空才会发送认证。SOCKS5 代理主机在建立连接时才解析，
/// 因此本函数保持同步，可供同步创建客户端的调用方使用。
void configureHttpClientProxy(
  HttpClient client,
  Uri proxy, {
  String username = '',
  String password = '',
}) {
  final hasCredentials = username.isNotEmpty && password.isNotEmpty;
  final host = proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host;
  if (proxy.scheme != 'socks5') {
    // 凭据写进 PROXY 串，dart:io 才会对普通请求和 HTTPS 隧道预先发送。
    final credentials = hasCredentials ? '$username:$password@' : '';
    client.findProxy = (_) => 'PROXY $credentials$host:${proxy.port}';
    return;
  }
  client.findProxy = (_) => 'DIRECT';
  Future<InternetAddress>? resolving;
  Future<InternetAddress> resolveProxy() => resolving ??= () async {
    try {
      return InternetAddress.tryParse(proxy.host) ??
          (await InternetAddress.lookup(
            proxy.host,
          ).timeout(const Duration(seconds: 30))).first;
    } catch (_) {
      // 解析失败不缓存，下一次连接重新解析。
      resolving = null;
      rethrow;
    }
  }();
  client.connectionFactory = (uri, _, _) async {
    final result = Completer<Socket>();
    ConnectionTask<Socket>? transportTask;
    Socket? transport;
    var cancelled = false;

    void checkCancellation() {
      if (cancelled) {
        throw const SocketException('Proxy connection cancelled');
      }
    }

    // 库只在 SOCKS 握手完成后返回 socket。限定在本次连接的 Zone 内持有
    // TCP 句柄，让取消能中断握手，不影响其他客户端的 Socket.connect。
    final connection = IOOverrides.runZoned(
      () async {
        final address = await resolveProxy();
        checkCancellation();
        final socket = await SocksTCPClient.connect(
          [
            ProxySettings(
              address,
              proxy.port,
              username: hasCredentials ? username : null,
              password: hasCredentials ? password : null,
            ),
          ],
          // 目标主机交给代理端解析。
          InternetAddress(uri.host, type: InternetAddressType.unix),
          uri.port,
        );
        checkCancellation();
        return uri.scheme == 'https' ? await socket.secure(uri.host) : socket;
      },
      socketConnect:
          (host, port, {sourceAddress, sourcePort = 0, timeout}) async {
            checkCancellation();
            final task = await Socket.startConnect(
              host,
              port,
              sourceAddress: sourceAddress,
              sourcePort: sourcePort,
            );
            transportTask = task;
            if (cancelled) {
              task.cancel();
            }
            final socket = await task.socket;
            transport = socket;
            if (cancelled) {
              socket.destroy();
              checkCancellation();
            }
            return socket;
          },
    );
    connection.then(
      (socket) {
        if (cancelled) {
          socket.destroy();
        } else {
          result.complete(socket);
        }
      },
      onError: (Object error, StackTrace stack) {
        transport?.destroy();
        if (!result.isCompleted) {
          result.completeError(error, stack);
        }
      },
    );
    return ConnectionTask.fromSocket(result.future, () {
      cancelled = true;
      transportTask?.cancel();
      transport?.destroy();
      if (!result.isCompleted) {
        result.completeError(
          const SocketException('Proxy connection cancelled'),
        );
      }
    });
  };
}
