// 职责: 提供 Reveric 所需的 Anthropic Messages API 入口。
// 关联文件:
//   third/ai_clients_dart/packages/anthropic_sdk_dart/lib/src/resources/messages_resource.dart
//   third/ai_clients_dart/packages/anthropic_sdk_dart/lib/src/client/config.dart

import 'package:http/http.dart' as http;

import '../auth/auth_provider.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/error_interceptor.dart';
import '../interceptors/interceptor.dart';
import '../interceptors/logging_interceptor.dart';
import '../resources/messages_resource.dart';
import 'config.dart';
import 'interceptor_chain.dart';
import 'request_builder.dart';
import 'retry_wrapper.dart';

class AnthropicClient {
  AnthropicClient({
    AnthropicConfig? config,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) : config = config ?? const AnthropicConfig(),
       _httpClient = httpClient ?? http.Client(),
       _streamClientFactory = streamClientFactory,
       _ownsHttpClient = httpClient == null {
    _initialize();
  }

  factory AnthropicClient.fromEnvironment({http.Client? httpClient}) {
    return AnthropicClient(
      config: AnthropicConfig.fromEnvironment(),
      httpClient: httpClient,
    );
  }

  factory AnthropicClient.withApiKey(
    String apiKey, {
    String? baseUrl,
    Map<String, String>? defaultHeaders,
    http.Client? httpClient,
  }) {
    return AnthropicClient(
      config: AnthropicConfig(
        authProvider: ApiKeyProvider(apiKey),
        baseUrl: baseUrl ?? 'https://api.anthropic.com',
        defaultHeaders: defaultHeaders ?? const {},
      ),
      httpClient: httpClient,
    );
  }

  final AnthropicConfig config;
  final http.Client _httpClient;
  final http.Client Function()? _streamClientFactory;
  final bool _ownsHttpClient;
  late final InterceptorChain _interceptorChain;
  late final RequestBuilder _requestBuilder;
  late final MessagesResource messages;
  bool _closed = false;

  void _initialize() {
    _requestBuilder = RequestBuilder(config: config);
    final interceptors = <Interceptor>[
      if (config.authProvider != null)
        AuthInterceptor(authProvider: config.authProvider!),
      LoggingInterceptor(
        logLevel: config.logLevel,
        redactionList: config.redactionList,
      ),
      const ErrorInterceptor(),
    ];
    _interceptorChain = InterceptorChain(
      interceptors: interceptors,
      httpClient: _httpClient,
      retryWrapper: config.retryPolicy.maxRetries > 0
          ? RetryWrapper(config: config)
          : null,
      ensureNotClosed: _ensureNotClosed,
    );
    messages = MessagesResource(
      config: config,
      httpClient: _httpClient,
      streamClientFactory: _streamClientFactory,
      interceptorChain: _interceptorChain,
      requestBuilder: _requestBuilder,
      ensureNotClosed: _ensureNotClosed,
    );
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  void _ensureNotClosed() {
    if (_closed) {
      throw StateError('Client has been closed');
    }
  }

  InterceptorChain get interceptorChain => _interceptorChain;

  RequestBuilder get requestBuilder => _requestBuilder;

  http.Client get httpClient => _httpClient;
}
