// 职责: 管理独立 OAuth 授权事务、刷新去重和绑定凭据的原子提交。
// 关联文件:
//   lib/shared/services/mcp/oauth/provider.dart
//   lib/shared/services/mcp/oauth/callback.dart
//   lib/shared/services/mcp/oauth/metadata.dart
//   lib/shared/services/mcp/settings_orchestrator.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:url_launcher/url_launcher.dart';
import '../../../database/app_database.dart';
import '../../../models/mcp/config.dart';
import '../../../models/mcp/tool_descriptor.dart';
import '../settings_orchestrator.dart';
import '../diagnostics.dart';
import 'callback.dart';
import 'metadata.dart';
import 'provider.dart';

class McpOAuthCoordinator {
  McpOAuthCoordinator(
    this.database,
    this.callbacks, {
    this.openBrowser = _openBrowser,
  });
  final AppDatabase database;
  final McpOAuthCallbacks callbacks;
  final Future<void> Function(Uri) openBrowser;
  final _sessions = <String, _Authorization>{};
  final _refreshes = <String, Future<sdk.OAuthTokens?>>{};
  final _invalidRefreshes = <String, String>{};
  final _generations = <String, int>{};
  bool _closed = false;
  bool isLoggingIn(String name) => _sessions.containsKey(name);
  static Future<void> _openBrowser(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('OAuth browser could not open');
    }
  }

  Future<McpServerConfig> _current(String name) async {
    final loaded = McpSettingsLoad.decode(
      await database.appSettingsDao.get(McpSettings.key),
    );
    final error = loaded.error ?? loaded.errors[name];
    if (error != null) {
      throw FormatException(error);
    }
    final config = loaded.settings.servers
        .where((s) => s.name == name)
        .firstOrNull;
    if (config == null || !config.enabled) {
      throw StateError('MCP server unavailable');
    }
    return config;
  }

  static String _key(McpServerConfig config) =>
      canonicalMcpJson(config.connection.toJson());
  Future<void> login(String name) async {
    if (_closed || _sessions.containsKey(name)) {
      throw StateError('OAuth transaction already active or closed');
    }
    final config = await _current(name);
    final connection = config.connection;
    if (connection is! McpHttpConfig) {
      throw StateError('OAuth requires HTTP');
    }
    if (connection.authMode == McpAuthMode.bearer ||
        connection.authMode == McpAuthMode.headers) {
      throw StateError('Explicit credentials cannot be replaced by OAuth');
    }
    callbacks.lastError = null;
    final session = _Authorization();
    _sessions[name] = session;
    session.deadline = Timer(
      const Duration(minutes: 5),
      () => cancel(name, reason: 'mcp_oauth_expired'),
    );
    sdk.silenceMcpLogs();
    sdk.StreamableHttpClientTransport? authorizationTransport;
    McpOAuthCallback? callback;
    try {
      final metadata = await McpOAuthMetadata.discover(
        Uri.parse(connection.url),
      );
      if (!identical(_sessions[name], session)) {
        throw StateError(session.reason);
      }
      callback = await callbacks.open(
        port: connection.oauth['callbackPort'] as int?,
      );
      session.cleanup = () async {
        await authorizationTransport?.close();
        await callback?.close();
      };
      // Empty when the user configured no pre-registered client, so every
      // login performs Dynamic Client Registration instead of reusing a
      // previously issued client ID as if the user had configured it.
      var registeredClient = const <String, dynamic>{};
      final provider = McpOAuthProvider(
        clientId: connection.oauth['clientId'] as String? ?? '',
        redirectUri: callback.uri,
        scopes: (connection.oauth['scopes'] as List? ?? []).cast<String>(),
        authorize: (uri) async {
          if (!identical(_sessions[name], session)) {
            throw StateError(session.reason);
          }
          callback!.expectedState = uri.queryParameters['state'];
          session.authorizationRequested = true;
          await openBrowser(uri);
        },
        registerClient: (client) async {
          if (!identical(_sessions[name], session)) {
            throw StateError(session.reason);
          }
          registeredClient = {
            'registeredClientId': client.clientId,
            if (client.clientSecret != null)
              'registeredClientSecret': client.clientSecret,
            'registeredAuthMethod': client.tokenEndpointAuthMethod,
          };
        },
        persistTokens: (tokens) async {
          if (!identical(_sessions[name], session)) {
            throw StateError(session.reason);
          }
          await _persist(
            config,
            tokens,
            metadata,
            client: registeredClient,
            allowed: () => identical(_sessions[name], session),
          );
        },
      );
      final transport = sdk.StreamableHttpClientTransport(
        Uri.parse(connection.url),
        opts: sdk.StreamableHttpClientTransportOptions(
          authProvider: provider,
          oauthUriValidator: metadata.allows,
          oauthRedirectUriValidator:
              McpOAuthCallbacks.acceptsRegisteredRedirect,
          requestInit: {'headers': connection.headers},
        ),
      );
      authorizationTransport = transport;
      // McpClient.connect closes failed handshakes, which would discard PKCE/state.
      // The authorization transport is independent of tool-client initialization.
      await transport.start();
      try {
        await transport
            .send(
              sdk.JsonRpcServerDiscoverRequest(
                id: 1,
                meta: sdk.buildProtocolRequestMeta(
                  protocolVersion: sdk.defaultProtocolVersion,
                  clientInfo: const sdk.Implementation(
                    name: 'Reveric',
                    version: '1',
                  ),
                  clientCapabilities: const sdk.ClientCapabilities(),
                ),
              ),
            )
            .timeout(const Duration(seconds: 30));
      } on sdk.UnauthorizedError {
        if (!session.authorizationRequested) {
          rethrow;
        }
      }
      if (!session.authorizationRequested) {
        throw StateError('Server did not request OAuth');
      }
      final uri = await Future.any<Uri>([
        callback.result,
        session.cancelled.future.then((_) => throw StateError(session.reason)),
      ]).timeout(const Duration(minutes: 5));
      if (uri.queryParameters.containsKey('error')) {
        throw StateError(
          'OAuth authorization denied: ${uri.queryParameters['error']}',
        );
      }
      for (final field in ['code', 'state']) {
        if (uri.queryParametersAll[field]?.length != 1 ||
            uri.queryParameters[field]!.isEmpty) {
          throw FormatException('Invalid OAuth callback $field');
        }
      }
      if (!identical(_sessions[name], session) ||
          _key(await _current(name)) != _key(config)) {
        throw StateError('OAuth configuration changed');
      }
      await transport.finishAuthRedirect(
        uri.queryParameters['code']!,
        state: uri.queryParameters['state']!,
        issuer: uri.queryParameters['iss'],
      );
      _invalidRefreshes.remove(name);
    } finally {
      if (identical(_sessions[name], session)) {
        _sessions.remove(name);
      }
      session.deadline?.cancel();
      await authorizationTransport?.close();
      await callback?.close();
    }
  }

  static const _registeredClientFields = [
    'registeredClientId',
    'registeredClientSecret',
    'registeredAuthMethod',
  ];

  /// [client] replaces the stored registered client when a login produced a
  /// new grant; refreshes pass null and keep the client that owns the grant.
  Future<void> _persist(
    McpServerConfig expected,
    sdk.OAuthTokens tokens,
    McpOAuthMetadata metadata, {
    Map<String, dynamic>? client,
    required bool Function() allowed,
  }) async {
    final connection = expected.connection as McpHttpConfig;
    final auth = <String, dynamic>{
      ...Map<String, dynamic>.from(connection.oauth)
        ..remove('expiresAt')
        ..remove('accessToken')
        ..remove('refreshToken')
        ..removeWhere(
          (key, _) => client != null && _registeredClientFields.contains(key),
        ),
      ...?client,
      'accessToken': tokens.accessToken,
      if (tokens.refreshToken != null) 'refreshToken': tokens.refreshToken,
      'issuer': metadata.issuer.toString(),
      'resource': metadata.resource.toString(),
      'tokenEndpoint': metadata.tokenEndpoint.toString(),
      if (tokens is sdk.OAuthAuthorizationCodeTokens &&
          tokens.expiresIn != null)
        'expiresAt': DateTime.now()
            .add(Duration(seconds: tokens.expiresIn!))
            .toUtc()
            .toIso8601String(),
    };
    await McpSettingsOrchestrator().update(
      database: database,
      change: (settings) {
        final current = settings.servers
            .where((s) => s.name == expected.name)
            .firstOrNull;
        if (_closed ||
            !allowed() ||
            current == null ||
            !current.enabled ||
            _key(current) != _key(expected)) {
          throw StateError(
            'OAuth credential commit belongs to an expired configuration',
          );
        }
        final replacement = current.copyWith(
          connection: McpHttpConfig(
            url: connection.url,
            authMode: McpAuthMode.oauth,
            headers: connection.headers,
            oauth: auth,
          ),
        );
        return McpSettings(
          settings.servers.map(
            (s) => s.name == expected.name ? replacement : s,
          ),
        );
      },
    );
  }

  Future<McpServerConfig> _usable(McpServerConfig config) async {
    final current = await _current(config.name);
    if (_closed ||
        _invalidRefreshes[config.name] == _key(current) ||
        current.connection is! McpHttpConfig ||
        canonicalMcpJson(
              (config.connection as McpHttpConfig).connectionIdentity(),
            ) !=
            canonicalMcpJson(
              (current.connection as McpHttpConfig).connectionIdentity(),
            )) {
      throw const McpNeedsAuth();
    }
    final connection = current.connection as McpHttpConfig;
    final auth = connection.oauth;
    final resource = auth['resource'] as String?;
    if (resource != null &&
        !McpOAuthMetadata.covers(
          Uri.parse(resource),
          Uri.parse(connection.url),
        )) {
      throw const McpNeedsAuth();
    }
    return current;
  }

  Future<sdk.OAuthTokens?> tokens(McpServerConfig config) async {
    config = await _usable(config);
    final auth = (config.connection as McpHttpConfig).oauth;
    final access = auth['accessToken'] as String?;
    if (access == null) {
      return null;
    }
    final expiry = auth['expiresAt'] as String?;
    if (expiry == null ||
        DateTime.parse(
          expiry,
        ).isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return sdk.OAuthIssuerBoundAuthorizationCodeTokens(
        accessToken: access,
        refreshToken: auth['refreshToken'] as String?,
        authorizationServerIssuer: auth['issuer'] as String,
        resource: Uri.parse(auth['resource'] as String),
      );
    }
    return _sharedRefresh(config);
  }

  /// Refreshes after the server rejected [rejectedAccess], regardless of the
  /// stored expiry: servers may revoke early or omit `expires_in`. When the
  /// stored token already differs, another caller replaced it and the request
  /// can simply be retried.
  Future<void> refreshRejected(
    McpServerConfig config,
    String rejectedAccess,
  ) async {
    config = await _usable(config);
    final auth = (config.connection as McpHttpConfig).oauth;
    if (auth['accessToken'] != rejectedAccess) {
      return;
    }
    await _sharedRefresh(config);
  }

  Future<sdk.OAuthTokens?> _sharedRefresh(McpServerConfig config) async {
    final existing = _refreshes[config.name];
    if (existing != null) {
      return existing;
    }
    final future = _refresh(config);
    _refreshes[config.name] = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshes[config.name], future)) {
        _refreshes.remove(config.name);
      }
    }
  }

  Future<sdk.OAuthTokens?> _refresh(McpServerConfig config) async {
    final generation = _generations[config.name] ?? 0;
    final connection = config.connection as McpHttpConfig;
    final auth = connection.oauth;
    final refresh = auth['refreshToken'] as String?;
    if (refresh == null) {
      throw const McpNeedsAuth();
    }
    final client = http.Client();
    try {
      final metadata = await McpOAuthMetadata.discover(
        Uri.parse(connection.url),
      );
      final resource = auth['resource'];
      if (metadata.issuer.toString() != auth['issuer'] ||
          resource is! String ||
          !McpOAuthMetadata.sameResource(
            metadata.resource,
            Uri.parse(resource),
          )) {
        throw StateError('OAuth issuer or resource changed');
      }
      final headers = <String, String>{};
      final body = {
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'resource': metadata.resource.toString(),
      };
      _authenticateClient(auth, headers, body);
      final response = await client
          .post(metadata.tokenEndpoint, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        final error = _oauthErrorCode(response.body);
        // Only these RFC 6749 errors mean the grant or client is permanently
        // rejected. Network failures, timeouts and 5xx stay retryable.
        if (error == 'invalid_grant' || error == 'invalid_client') {
          if ((_generations[config.name] ?? 0) == generation) {
            _invalidRefreshes[config.name] = _key(config);
          }
          throw const McpNeedsAuth();
        }
        throw StateError(
          'OAuth refresh HTTP ${response.statusCode}: ${_excerpt(response.body)}',
        );
      }
      final fresh = jsonDecode(response.body) as Map<String, dynamic>;
      final tokens = sdk.OAuthIssuerBoundAuthorizationCodeTokens(
        accessToken: fresh['access_token'] as String,
        refreshToken: fresh['refresh_token'] as String? ?? refresh,
        expiresIn: fresh['expires_in'] as int?,
        authorizationServerIssuer: metadata.issuer.toString(),
        resource: metadata.resource,
      );
      await _persist(
        config,
        tokens,
        metadata,
        allowed: () => (_generations[config.name] ?? 0) == generation,
      );
      return tokens;
    } finally {
      client.close();
    }
  }

  /// Authenticates token and revocation requests as the client that owns the
  /// grant: the registered client after DCR, otherwise the configured one.
  static void _authenticateClient(
    Map<String, dynamic> auth,
    Map<String, String> headers,
    Map<String, String> body,
  ) {
    final clientId =
        auth['registeredClientId'] as String? ??
        auth['clientId'] as String? ??
        '';
    body['client_id'] = clientId;
    final method = auth['registeredAuthMethod'] as String? ?? 'none';
    if (method == 'none') {
      return;
    }
    final secret = auth['registeredClientSecret'] as String?;
    if (secret == null || secret.isEmpty) {
      throw StateError('OAuth client requires $method but has no secret');
    }
    switch (method) {
      case 'client_secret_basic':
        final credentials = base64Encode(
          utf8.encode(
            '${Uri.encodeQueryComponent(clientId)}:'
            '${Uri.encodeQueryComponent(secret)}',
          ),
        );
        headers['Authorization'] = 'Basic $credentials';
      case 'client_secret_post':
        body['client_secret'] = secret;
      default:
        throw StateError('Unsupported OAuth client authentication $method');
    }
  }

  static String? _oauthErrorCode(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map && json['error'] is String
          ? json['error'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  static String _excerpt(String body) =>
      String.fromCharCodes(body.runes.take(512));

  /// Ends only the interactive authorization. A refresh running at the same
  /// time must still commit: the server may already have rotated the refresh
  /// token, and discarding its result would leave only the spent one stored.
  void cancel(String name, {String reason = 'mcp_oauth_cancelled'}) {
    final session = _sessions.remove(name);
    if (session != null && !session.cancelled.isCompleted) {
      session.reason = reason;
      session.cancelled.complete();
      unawaited(session.cleanup?.call());
    }
  }

  /// Cancels authorization and prevents refreshes already in flight from
  /// committing, for when the stored credentials are being edited, removed or
  /// signed out.
  void invalidate(String name) {
    cancel(name);
    _generations[name] = (_generations[name] ?? 0) + 1;
    _refreshes.remove(name);
  }

  Future<McpLogoutResult> revoke(McpServerConfig config) async {
    invalidate(config.name);
    final connection = config.connection;
    if (connection is! McpHttpConfig ||
        connection.authMode != McpAuthMode.oauth) {
      return const McpLogoutResult();
    }
    final token =
        connection.oauth['refreshToken'] ?? connection.oauth['accessToken'];
    if (token is! String || token.isEmpty) {
      return const McpLogoutResult();
    }
    final client = http.Client();
    try {
      final metadata = await McpOAuthMetadata.discover(
        Uri.parse(connection.url),
      );
      final endpoint = metadata.revocationEndpoint;
      if (endpoint == null) {
        return const McpLogoutResult();
      }
      final resource = connection.oauth['resource'];
      if (connection.oauth['issuer'] != metadata.issuer.toString() ||
          resource is! String ||
          !McpOAuthMetadata.sameResource(
            metadata.resource,
            Uri.parse(resource),
          )) {
        throw StateError('OAuth issuer or resource changed before revocation');
      }
      final headers = <String, String>{};
      final body = {
        'token': token,
        'token_type_hint': connection.oauth['refreshToken'] != null
            ? 'refresh_token'
            : 'access_token',
      };
      _authenticateClient(connection.oauth, headers, body);
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers.addAll(headers)
        ..bodyFields = body;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('OAuth revocation HTTP ${response.statusCode}');
      }
      return const McpLogoutResult(remoteAttempted: true, remoteRevoked: true);
    } catch (error) {
      return McpLogoutResult(
        remoteAttempted: true,
        diagnostic: mcpDiagnostic(error, config),
      );
    } finally {
      client.close();
    }
  }

  Future<McpLogoutResult> logout(String name) async {
    final result = await revoke(await _current(name));
    await McpSettingsOrchestrator().update(
      database: database,
      change: (settings) => McpSettings(
        settings.servers.map((s) {
          if (s.name != name || s.connection is! McpHttpConfig) {
            return s;
          }
          final http = s.connection as McpHttpConfig;
          return s.copyWith(
            connection: McpHttpConfig(
              url: http.url,
              authMode: http.authMode,
              headers: http.headers,
              bearerToken: http.bearerToken,
              oauth: {
                for (final key in ['clientId', 'scopes', 'callbackPort'])
                  if (http.oauth.containsKey(key)) key: http.oauth[key],
              },
            ),
          );
        }),
      ),
    );
    return result;
  }

  Future<void> close() async {
    _closed = true;
    for (final name in _sessions.keys.toList()) {
      cancel(name);
    }
  }
}

class _Authorization {
  final cancelled = Completer<void>();
  bool authorizationRequested = false;
  String reason = 'mcp_oauth_cancelled';
  Timer? deadline;
  Future<void> Function()? cleanup;
}

class McpLogoutResult {
  const McpLogoutResult({
    this.remoteAttempted = false,
    this.remoteRevoked = false,
    this.diagnostic,
  });
  final bool remoteAttempted;
  final bool remoteRevoked;
  final String? diagnostic;
  bool get remoteFailed => remoteAttempted && !remoteRevoked;
}
