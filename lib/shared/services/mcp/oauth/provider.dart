// 职责: 将 SDK OAuth 授权事务的 token、重定向与持久化回调接到应用。
// 关联文件:
//   lib/shared/services/mcp/oauth/coordinator.dart
//   lib/shared/services/mcp/oauth/metadata.dart
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import '../diagnostics.dart';

class McpOAuthProvider
    implements
        sdk.OAuthAuthorizationCodeProvider,
        sdk.OAuthClientRegistrationListener {
  McpOAuthProvider({
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.persistTokens,
    required this.authorize,
    required this.registerClient,
  });
  @override
  final String clientId;
  @override
  final Uri redirectUri;
  @override
  final List<String> scopes;
  @override
  String? get clientSecret => null;
  final Future<void> Function(sdk.OAuthTokens tokens) persistTokens;
  final Future<void> Function(Uri uri) authorize;
  final Future<void> Function(sdk.OAuthRegisteredClient client) registerClient;
  @override
  Future<sdk.OAuthTokens?> tokens() async => null;
  @override
  Future<void> redirectToAuthorization() =>
      throw StateError('OAuth requires validated authorization metadata');
  @override
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri) =>
      authorize(authorizationUri);
  @override
  Future<void> saveTokens(sdk.OAuthTokens tokens) => persistTokens(tokens);
  @override
  Future<void> saveClientRegistration(sdk.OAuthRegisteredClient client) =>
      registerClient(client);
}

class McpStoredTokenProvider implements sdk.OAuthClientProvider {
  McpStoredTokenProvider(this.readTokens);
  final Future<sdk.OAuthTokens?> Function() readTokens;
  bool _hadTokens = false;
  @override
  Future<sdk.OAuthTokens?> tokens() async {
    final tokens = await readTokens();
    _hadTokens = tokens != null;
    return tokens;
  }

  @override
  Future<void> redirectToAuthorization() =>
      throw McpNeedsAuth(requestRejected: _hadTokens);
}
