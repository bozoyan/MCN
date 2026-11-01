// 职责: 提供 Reveric 所需的 Gemini 内容生成与嵌入 API 入口。
// 关联文件:
//   third/ai_clients_dart/packages/googleai_dart/lib/src/resources/models_resource.dart
//   third/ai_clients_dart/packages/googleai_dart/lib/src/client/config.dart

import 'package:http/http.dart' as http;

import '../auth/auth_provider.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/error_interceptor.dart';
import '../interceptors/logging_interceptor.dart';
import '../resources/models_resource.dart';
import 'config.dart';
import 'interceptor_chain.dart';
import 'request_builder.dart';
import 'retry_wrapper.dart';

class GoogleAIClient {
  GoogleAIClient({
    GoogleAIConfig? config,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) : config = config ?? const GoogleAIConfig(),
       _httpClient = httpClient ?? http.Client(),
       _streamClientFactory = streamClientFactory,
       _ownsHttpClient = httpClient == null {
    _requestBuilder = RequestBuilder(config: this.config);
    _interceptorChain = InterceptorChain(
      httpClient: _httpClient,
      interceptors: [
        AuthInterceptor(config: this.config),
        LoggingInterceptor(config: this.config),
        const ErrorInterceptor(),
      ],
      retryWrapper: RetryWrapper(config: this.config),
      ensureNotClosed: _ensureNotClosed,
    );
    models = ModelsResource(
      config: this.config,
      httpClient: _httpClient,
      streamClientFactory: _streamClientFactory,
      interceptorChain: _interceptorChain,
      requestBuilder: _requestBuilder,
      ensureNotClosed: _ensureNotClosed,
    );
  }

  factory GoogleAIClient.fromEnvironment({
    String envVarName = 'GOOGLE_GENAI_API_KEY',
    ApiVersion apiVersion = ApiVersion.v1beta,
    Duration timeout = const Duration(minutes: 2),
    RetryPolicy retryPolicy = RetryPolicy.defaultPolicy,
    http.Client? httpClient,
  }) {
    return GoogleAIClient(
      config: GoogleAIConfig.fromEnvironment(
        envVarName: envVarName,
        apiVersion: apiVersion,
        timeout: timeout,
        retryPolicy: retryPolicy,
      ),
      httpClient: httpClient,
    );
  }

  factory GoogleAIClient.withApiKey(
    String apiKey, {
    String? baseUrl,
    Map<String, String>? defaultHeaders,
    http.Client? httpClient,
  }) {
    return GoogleAIClient(
      config: GoogleAIConfig(
        authProvider: ApiKeyProvider(apiKey),
        baseUrl: baseUrl ?? 'https://generativelanguage.googleapis.com',
        defaultHeaders: defaultHeaders ?? const {},
      ),
      httpClient: httpClient,
    );
  }

  final GoogleAIConfig config;
  final http.Client _httpClient;
  final http.Client Function()? _streamClientFactory;
  final bool _ownsHttpClient;
  late final RequestBuilder _requestBuilder;
  late final InterceptorChain _interceptorChain;
  late final ModelsResource models;
  bool _closed = false;

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
