// 职责: 校验 OAuth 发现文档并限定 SDK 可访问的认证端点。
// 关联文件:
//   lib/shared/services/mcp/oauth/coordinator.dart
//   lib/shared/services/mcp/oauth/provider.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart' as sdk;

class McpOAuthMetadata {
  McpOAuthMetadata({
    required this.resource,
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.discoveryUris,
    this.registrationEndpoint,
    this.revocationEndpoint,
  });
  final Uri resource;
  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? registrationEndpoint;
  final Uri? revocationEndpoint;
  final Set<Uri> discoveryUris;

  bool allows(Uri uri, sdk.OAuthEndpointKind kind) => {
    issuer,
    authorizationEndpoint,
    tokenEndpoint,
    registrationEndpoint,
    revocationEndpoint,
    ...discoveryUris,
  }.contains(uri);

  /// Whether a token bound to [resource] may be sent to [endpoint]. Matches
  /// the SDK: same origin, and either the same path or the origin root, which
  /// servers often declare when publishing metadata at the root.
  static bool covers(Uri resource, Uri endpoint) =>
      !resource.hasFragment &&
      resource.scheme == endpoint.scheme &&
      resource.host == endpoint.host &&
      resource.port == endpoint.port &&
      (_path(resource) == _path(endpoint) || _path(resource) == '/');

  /// Compares parsed URIs so case, default ports and an empty root path do
  /// not count as a different resource.
  static bool sameResource(Uri a, Uri b) =>
      a.replace(path: _path(a)) == b.replace(path: _path(b));

  static String _path(Uri uri) => uri.path.isEmpty ? '/' : uri.path;

  static bool secure(Uri uri) =>
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      (uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              ['127.0.0.1', 'localhost', '::1'].contains(uri.host)));

  static Future<McpOAuthMetadata> discover(Uri endpoint) async {
    final client = http.Client();
    try {
      Future<Map<String, dynamic>> read(Uri uri) async {
        if (!secure(uri)) {
          throw const FormatException(
            'OAuth endpoint requires HTTPS or loopback',
          );
        }
        final request = http.Request('GET', uri)..followRedirects = false;
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw _DiscoveryHttpError(response.statusCode);
        }
        if (response.bodyBytes.length > 128 * 1024) {
          throw const FormatException('OAuth metadata too large');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final tried = <Uri>{};
      Future<Map<String, dynamic>> firstDocument(List<Uri> candidates) async {
        for (final uri in candidates.toSet()) {
          tried.add(uri);
          try {
            return await read(uri);
          } on _DiscoveryHttpError catch (error) {
            if (error.status != 404) {
              rethrow;
            }
          }
        }
        throw const _DiscoveryHttpError(404);
      }

      Map<String, dynamic> protectedRaw;
      try {
        protectedRaw = await firstDocument([
          endpoint.replace(
            path:
                '/.well-known/oauth-protected-resource${endpoint.path == '/' ? '' : endpoint.path}',
            query: null,
            fragment: null,
          ),
          endpoint.replace(
            path: '/.well-known/oauth-protected-resource',
            query: null,
            fragment: null,
          ),
        ]);
      } on _DiscoveryHttpError catch (error) {
        if (error.status != 404) {
          rethrow;
        }
        // Read only the challenge headers; do not wait for a public SSE body.
        final response = await client
            .send(http.Request('GET', endpoint)..followRedirects = false)
            .timeout(const Duration(seconds: 15));
        final challenge = response.headers['www-authenticate'] ?? '';
        await response.stream.listen(null).cancel();
        final match = RegExp(
          r'resource_metadata\s*=\s*"([^"]+)"',
          caseSensitive: false,
        ).firstMatch(challenge);
        if (match == null) {
          rethrow;
        }
        final uri = Uri.parse(match.group(1)!);
        tried.add(uri);
        protectedRaw = await read(uri);
      }
      final protected = sdk.OAuthProtectedResourceMetadataDocument.fromJson(
        protectedRaw,
      );
      if (!covers(protected.resource, endpoint) ||
          protected.authorizationServers.isEmpty) {
        throw const FormatException(
          'OAuth resource identity mismatch or missing authorization server',
        );
      }
      final issuer = protected.authorizationServers.first;
      final path = issuer.path == '/'
          ? ''
          : issuer.path.replaceFirst(RegExp(r'/$'), '');
      final raw = await firstDocument([
        issuer.replace(
          path: '/.well-known/oauth-authorization-server$path',
          query: null,
        ),
        issuer.replace(
          path: '/.well-known/openid-configuration$path',
          query: null,
        ),
        issuer.replace(
          path: '$path/.well-known/openid-configuration',
          query: null,
        ),
        issuer.replace(
          path: '$path/.well-known/oauth-authorization-server',
          query: null,
        ),
      ]);
      final metadata = sdk.OAuthAuthorizationServerMetadataDocument.fromJson(
        raw,
      );
      if (metadata.issuer != issuer ||
          metadata.authorizationEndpoint == null ||
          metadata.tokenEndpoint == null ||
          !(metadata.codeChallengeMethodsSupported?.contains('S256') ??
              false)) {
        throw const FormatException(
          'OAuth issuer, endpoints or PKCE metadata invalid',
        );
      }
      final endpoints = [
        metadata.authorizationEndpoint!,
        metadata.tokenEndpoint!,
        if (metadata.registrationEndpoint != null)
          metadata.registrationEndpoint!,
        if (raw['revocation_endpoint'] is String)
          Uri.parse(raw['revocation_endpoint'] as String),
      ];
      if (!endpoints.every(secure)) {
        throw const FormatException('Unsafe OAuth endpoint');
      }
      return McpOAuthMetadata(
        resource: protected.resource,
        issuer: issuer,
        authorizationEndpoint: metadata.authorizationEndpoint!,
        tokenEndpoint: metadata.tokenEndpoint!,
        registrationEndpoint: metadata.registrationEndpoint,
        revocationEndpoint: raw['revocation_endpoint'] is String
            ? Uri.parse(raw['revocation_endpoint'] as String)
            : null,
        discoveryUris: tried,
      );
    } finally {
      client.close();
    }
  }
}

class _DiscoveryHttpError implements Exception {
  const _DiscoveryHttpError(this.status);
  final int status;
  @override
  String toString() => 'OAuth discovery HTTP $status';
}
