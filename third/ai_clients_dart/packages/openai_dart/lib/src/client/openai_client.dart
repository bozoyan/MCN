// 职责: 提供 Reveric 所需的 OpenAI Chat Completions 与 Embeddings API 入口。
// 关联文件:
//   third/ai_clients_dart/packages/openai_dart/lib/src/resources/chat_resource.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/resources/embeddings_resource.dart
//   third/ai_clients_dart/packages/openai_dart/lib/src/client/config.dart

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../auth/auth_provider.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/error_interceptor.dart';
import '../interceptors/interceptor.dart';
import '../interceptors/logging_interceptor.dart';
import '../resources/chat_resource.dart';
import '../resources/embeddings_resource.dart';
import 'config.dart';
import 'interceptor_chain.dart';
import 'request_builder.dart';
import 'retry_wrapper.dart';

class OpenAIClient {
  OpenAIClient({
    OpenAIConfig? config,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) : _config = config ?? const OpenAIConfig(),
       _httpClient = httpClient ?? http.Client(),
       _streamClientFactory = streamClientFactory ?? http.Client.new,
       _ownsHttpClient = httpClient == null {
    _initializeLogging();
    _initializeInterceptorChain();
    _requestBuilder = RequestBuilder(config: _config);
  }

  factory OpenAIClient.fromEnvironment({
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) {
    return OpenAIClient(
      config: OpenAIConfig.fromEnvironment(),
      httpClient: httpClient,
      streamClientFactory: streamClientFactory,
    );
  }

  factory OpenAIClient.withApiKey(
    String apiKey, {
    String? baseUrl,
    Map<String, String>? defaultHeaders,
    String? organization,
    String? project,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) {
    return OpenAIClient(
      config: OpenAIConfig(
        authProvider: ApiKeyProvider(apiKey),
        baseUrl: baseUrl ?? 'https://api.openai.com/v1',
        defaultHeaders: defaultHeaders ?? const {},
        organization: organization,
        project: project,
      ),
      httpClient: httpClient,
      streamClientFactory: streamClientFactory,
    );
  }

  final OpenAIConfig _config;
  final http.Client _httpClient;
  final http.Client Function() _streamClientFactory;
  final bool _ownsHttpClient;
  late final InterceptorChain _interceptorChain;
  late final RequestBuilder _requestBuilder;
  Logger? _logger;
  bool _closed = false;

  OpenAIConfig get config => _config;

  Logger? get logger => _logger;

  InterceptorChain get interceptorChain => _interceptorChain;

  void _initializeLogging() {
    if (_config.logLevel case final level?) {
      _logger = Logger('OpenAIClient')..level = level;
    }
  }

  void _initializeInterceptorChain() {
    final interceptors = <Interceptor>[];
    if (_config.authProvider case final authProvider?) {
      interceptors.add(AuthInterceptor(authProvider: authProvider));
    }
    if (_config.logLevel != null) {
      _logger ??= Logger('OpenAIClient');
      interceptors.add(
        LoggingInterceptor(
          logger: _logger!,
          logRequestBody: _config.logLevel == Level.FINEST,
          logResponseBody: _config.logLevel == Level.FINEST,
        ),
      );
    }
    interceptors.add(const ErrorInterceptor());

    _interceptorChain = InterceptorChain(
      interceptors: interceptors,
      httpClient: _httpClient,
      retryWrapper: _config.retryPolicy.maxRetries > 0
          ? RetryWrapper(config: _config)
          : null,
      timeout: _config.timeout,
      ensureNotClosed: _ensureNotClosed,
    );
  }

  ChatResource? _chat;

  ChatResource get chat => _chat ??= ChatResource(
    config: config,
    httpClient: _httpClient,
    interceptorChain: _interceptorChain,
    requestBuilder: _requestBuilder,
    ensureNotClosed: _ensureNotClosed,
    streamClientFactory: _streamClientFactory,
  );

  EmbeddingsResource? _embeddings;

  EmbeddingsResource get embeddings => _embeddings ??= EmbeddingsResource(
    config: config,
    httpClient: _httpClient,
    interceptorChain: _interceptorChain,
    requestBuilder: _requestBuilder,
    ensureNotClosed: _ensureNotClosed,
  );

  void _ensureNotClosed() {
    if (_closed) {
      throw StateError('Client has been closed');
    }
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
}
