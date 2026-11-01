// 职责: 接收桌面 loopback 或 Android 深链回调并严格匹配事务地址。
// 关联文件:
//   lib/shared/services/mcp/oauth/coordinator.dart
//   lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';

class McpOAuthCallbacks {
  static final mobileUri = Uri.parse('ai.reveric://mcp/oauth/callback');
  static bool acceptsRegisteredRedirect(Uri uri) =>
      uri.scheme == mobileUri.scheme &&
      uri.host == mobileUri.host &&
      uri.path == mobileUri.path &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
  final _mobile = StreamController<Uri>.broadcast();
  StreamSubscription<Uri>? _subscription;
  String? lastError;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _subscription != null) {
      return;
    }
    final links = AppLinks();
    _subscription = links.uriLinkStream.listen(dispatch);
    final initial = await links.getInitialLink();
    if (initial != null) {
      dispatch(initial);
    }
  }

  void dispatch(Uri uri) {
    if (!_matches(uri, mobileUri)) {
      return;
    }
    if (!_mobile.hasListener) {
      lastError = 'mcp_oauth_transaction_missing';
      return;
    }
    _mobile.add(uri);
  }

  static bool _matches(Uri uri, Uri expected) =>
      uri.scheme == expected.scheme &&
      uri.host == expected.host &&
      uri.port == expected.port &&
      uri.path == expected.path &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;

  Future<McpOAuthCallback> open({int? port, bool? mobile}) async {
    if (mobile ?? Platform.isAndroid) {
      final callback = McpOAuthCallback._(mobileUri);
      callback.subscription = _mobile.stream.listen(callback.accept);
      return callback;
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port ?? 0,
    );
    final callback = McpOAuthCallback._(
      Uri.parse('http://127.0.0.1:${server.port}/mcp/oauth/callback'),
    );
    callback.server = server;
    callback.httpSubscription = server.listen((request) async {
      final uri = callback.uri.replace(
        path: request.uri.path,
        query: request.uri.query,
      );
      if (request.method != 'GET' ||
          request.uri.path != callback.uri.path ||
          callback.received.isCompleted) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.statusCode = callback.accept(uri)
            ? HttpStatus.noContent
            : HttpStatus.badRequest;
      }
      await request.response.close();
    });
    return callback;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _mobile.close();
  }
}

class McpOAuthCallback {
  McpOAuthCallback._(this.uri);
  final Uri uri;
  bool _closed = false;
  final received = Completer<Uri>();
  String? expectedState;
  HttpServer? server;
  StreamSubscription<Uri>? subscription;
  StreamSubscription<HttpRequest>? httpSubscription;
  Future<Uri> get result => received.future;
  bool accept(Uri value) {
    if (!McpOAuthCallbacks._matches(value, uri) ||
        received.isCompleted ||
        expectedState == null ||
        value.queryParameters['state'] != expectedState) {
      return false;
    }
    received.complete(value);
    return true;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await subscription?.cancel();
    await httpSubscription?.cancel();
    await server?.close(force: true);
  }
}
