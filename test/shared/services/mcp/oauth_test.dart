// 职责: 用可控服务验证认证识别、SDK PKCE 回调及 token 保存刷新边界。
// 关联文件:
//   lib/shared/services/mcp/settings_service.dart
//   lib/shared/services/mcp/oauth/coordinator.dart
//   lib/shared/services/mcp/oauth/callback.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/mcp/diagnostics.dart';
import 'package:reveric/shared/services/mcp/oauth/callback.dart';
import 'package:reveric/shared/services/mcp/oauth/coordinator.dart';
import 'package:reveric/shared/services/mcp/oauth/metadata.dart';
import 'package:reveric/shared/services/mcp/settings_orchestrator.dart';
import 'package:reveric/shared/services/mcp/settings_service.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';
import 'package:reveric/shared/services/mcp/tool_dispatcher.dart';
import 'adapter_test.dart' show reply;
import 'runtime_test.dart' show FakeConnection;

class MobileCallbacks extends McpOAuthCallbacks {
  @override
  Future<McpOAuthCallback> open({int? port, bool? mobile}) =>
      super.open(mobile: true);
}

void main() {
  test('protected resource matching follows the SDK origin and path rules', () {
    final endpoint = Uri.parse('https://Host.example:443/mcp');
    for (final (resource, covered) in [
      ('https://host.example', true),
      ('https://host.example/', true),
      ('HTTPS://HOST.EXAMPLE/mcp', true),
      ('https://host.example/other', false),
      ('https://host.example:8443/mcp', false),
      ('http://host.example/mcp', false),
      ('https://other.example/mcp', false),
      ('https://host.example/mcp#token', false),
    ]) {
      expect(
        McpOAuthMetadata.covers(Uri.parse(resource), endpoint),
        covered,
        reason: resource,
      );
    }
    expect(
      McpOAuthMetadata.sameResource(
        Uri.parse('https://host.example'),
        Uri.parse('HTTPS://host.example:443/'),
      ),
      true,
    );
  });
  for (final scenario in [
    'ordinary401',
    'discover',
    'bearer',
    'headers',
    'server_error_text',
  ]) {
    test(
      'background authentication identification: $scenario',
      () async {
        final db = AppDatabase.forTest(NativeDatabase.memory());
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final root = 'http://127.0.0.1:${server.port}';
        var registrations = 0;
        var browserOpens = 0;
        final receivedAuthorization = <String?>[];
        server.listen((request) async {
          Map<String, dynamic> body = {};
          if (request.uri.path == '/mcp') {
            receivedAuthorization.add(request.headers.value('authorization'));
            if (scenario == 'server_error_text') {
              final rpc =
                  jsonDecode(await utf8.decoder.bind(request).join()) as Map;
              body = {
                'jsonrpc': '2.0',
                'id': rpc['id'],
                'error': {
                  'code': 0,
                  'message':
                      'Error POSTing to endpoint (HTTP 401): simulated business error',
                },
              };
            } else {
              request.response.statusCode = 401;
              request.response.headers.set('www-authenticate', 'Bearer');
            }
          } else if (scenario != 'ordinary401' &&
              request.uri.path == '/.well-known/oauth-protected-resource/mcp') {
            body = {
              'resource': '$root/mcp',
              'authorization_servers': [root],
            };
          } else if (scenario != 'ordinary401' &&
              request.uri.path == '/.well-known/oauth-authorization-server') {
            body = {
              'issuer': root,
              'authorization_endpoint': '$root/authorize',
              'token_endpoint': '$root/token',
              'registration_endpoint': '$root/register',
              'response_types_supported': ['code'],
              'code_challenge_methods_supported': ['S256'],
            };
          } else {
            if (request.uri.path == '/register') {
              registrations++;
            }
            request.response.statusCode = 404;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        });
        final authMode = switch (scenario) {
          'bearer' => McpAuthMode.bearer,
          'headers' => McpAuthMode.headers,
          _ => McpAuthMode.none,
        };
        final config = McpServerConfig(
          name: 'notes',
          enabled: true,
          connection: McpHttpConfig(
            url: '$root/mcp',
            authMode: authMode,
            bearerToken: scenario == 'bearer' ? 'explicit-token' : null,
            headers: scenario == 'headers'
                ? {'Authorization': 'Custom explicit-token'}
                : {},
          ),
        );
        await McpSettingsOrchestrator().save(
          database: db,
          config: config,
          create: true,
        );
        final service = McpSettingsService(
          db,
          supportsStdio: false,
          openBrowser: (_) async {
            browserOpens++;
          },
        );
        try {
          await service.initialized;
          await expectLater(
            service.runtime.ensureReady('notes'),
            throwsA(anything),
          );
          expect(
            service.runtime.states['notes']!.status,
            scenario == 'discover'
                ? McpConnectionStatus.needs_auth
                : McpConnectionStatus.error,
            reason: service.runtime.states['notes']!.error,
          );
          expect(registrations, 0);
          expect(browserOpens, 0);
          expect(
            McpSettings.decode(
              await db.appSettingsDao.get(McpSettings.key),
            ).servers.single.toJson(),
            config.toJson(),
          );
          expect(receivedAuthorization, isNotEmpty);
          if (scenario == 'bearer') {
            expect(
              receivedAuthorization,
              everyElement('Bearer explicit-token'),
            );
          } else if (scenario == 'headers') {
            expect(
              receivedAuthorization,
              everyElement('Custom explicit-token'),
            );
          }
        } finally {
          await service.close();
          await server.close(force: true);
          await db.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  for (final scenario in [
    'refresh',
    'no_refresh',
    'manual_client',
    'bad_state',
    'bad_issuer',
    'cancel',
    'changed_config',
    'revocation_failure',
    'independent_origin',
    'background',
    'persistence_failure',
    'cancelled_refresh',
    'login_cancelled_during_refresh',
    'confidential_client',
    'refresh_unavailable',
    'refresh_revoked',
    'root_resource',
    'unnormalized_url',
  ]) {
    test(
      'SDK OAuth $scenario preserves transaction and credential boundaries',
      () async {
        final db = AppDatabase.forTest(NativeDatabase.memory());
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final root = 'http://127.0.0.1:${server.port}';
        final authServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final authRoot = scenario == 'independent_origin'
            ? 'http://localhost:${authServer.port}'
            : root;
        String? challenge;
        var registrationCount = 0;
        var exchanges = 0;
        var refreshes = 0;
        var holdAuthorization = false;
        final confidential = scenario == 'confidential_client';
        // Many servers publish metadata at the origin root and declare the
        // origin itself as the protected resource.
        final rootResource = scenario == 'root_resource';
        final clientAuthorization =
            'Basic ${base64Encode(utf8.encode('fixture-client:fixture-secret'))}';
        bool clientRejected(HttpRequest request) =>
            confidential &&
            request.headers.value('authorization') != clientAuthorization;
        Future<void> Function()? beforeRefreshResponse;
        Future<void> handle(HttpRequest request) async {
          Map<String, dynamic> body;
          switch (request.uri.path) {
            case '/mcp':
              request.response.statusCode = 401;
              request.response.headers.set(
                'www-authenticate',
                rootResource
                    ? 'Bearer resource_metadata="$root/.well-known/oauth-protected-resource"'
                    : 'Bearer resource_metadata="$root/.well-known/oauth-protected-resource/mcp"',
              );
              body = {'error': 'unauthorized'};
            case '/.well-known/oauth-protected-resource/mcp' when !rootResource:
              body = {
                'resource': '$root/mcp',
                'authorization_servers': [authRoot],
              };
            case '/.well-known/oauth-protected-resource' when rootResource:
              body = {
                'resource': root,
                'authorization_servers': [authRoot],
              };
            case '/.well-known/oauth-authorization-server':
              body = {
                'issuer': authRoot,
                'authorization_endpoint': '$authRoot/authorize',
                'token_endpoint': '$authRoot/token',
                'registration_endpoint': '$authRoot/register',
                'revocation_endpoint': '$authRoot/revoke',
                'authorization_response_iss_parameter_supported': true,
                'response_types_supported': ['code'],
                'code_challenge_methods_supported': ['S256'],
                'token_endpoint_auth_methods_supported': [
                  confidential ? 'client_secret_basic' : 'none',
                ],
              };
            case '/register':
              registrationCount++;
              body = {
                'client_id': 'fixture-client',
                if (confidential) 'client_secret': 'fixture-secret',
                'token_endpoint_auth_method': confidential
                    ? 'client_secret_basic'
                    : 'none',
              };
              request.response.statusCode = 201;
            case '/token':
              final fields = Uri.splitQueryString(
                await utf8.decoder.bind(request).join(),
              );
              if (clientRejected(request)) {
                request.response.statusCode = 401;
                body = {'error': 'invalid_client'};
              } else if (fields['grant_type'] == 'authorization_code') {
                exchanges++;
                final actual = base64Url
                    .encode(
                      sha256
                          .convert(utf8.encode(fields['code_verifier']!))
                          .bytes,
                    )
                    .replaceAll('=', '');
                expect(actual, challenge);
                body = {
                  'access_token': 'access-1',
                  if (scenario != 'no_refresh') 'refresh_token': 'refresh-1',
                  'token_type': 'Bearer',
                  'expires_in': scenario == 'no_refresh' ? 3600 : 1,
                };
              } else {
                refreshes++;
                expect(fields['refresh_token'], 'refresh-1');
                await beforeRefreshResponse?.call();
                if (scenario == 'refresh_unavailable' && refreshes == 1) {
                  request.response.statusCode = 503;
                  body = {'error': 'temporarily_unavailable'};
                } else if (scenario == 'refresh_revoked') {
                  request.response.statusCode = 400;
                  body = {'error': 'invalid_grant'};
                } else {
                  body = {
                    'access_token': 'access-2',
                    if (scenario == 'login_cancelled_during_refresh')
                      'refresh_token': 'refresh-2',
                    'token_type': 'Bearer',
                    'expires_in': 3600,
                  };
                }
              }
            case '/revoke':
              request.response.statusCode =
                  scenario == 'revocation_failure' || clientRejected(request)
                  ? 503
                  : 200;
              body = {};
            default:
              request.response.statusCode = 404;
              body = {'error': 'not_found'};
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        }

        server.listen(handle);
        authServer.listen(handle);
        final callbacks = scenario == 'background'
            ? MobileCallbacks()
            : McpOAuthCallbacks();
        McpSettingsService? service;
        final toolConnections = <FakeConnection>[];
        late final McpOAuthCoordinator coordinator;
        Future<void> openBrowser(Uri uri) async {
          challenge = uri.queryParameters['code_challenge'];
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          if (holdAuthorization) {
            return;
          }
          if (scenario == 'cancel') {
            coordinator.cancel('notes');
            return;
          }
          if (scenario == 'changed_config') {
            await McpSettingsOrchestrator().update(
              database: db,
              change: (settings) => McpSettings(
                settings.servers.map((s) => s.copyWith(enabled: false)),
              ),
            );
          }
          final callbackUri = redirect.replace(
            queryParameters: {
              'code': 'fixture-code',
              'state': scenario == 'bad_state'
                  ? 'wrong'
                  : uri.queryParameters['state']!,
              'iss': scenario == 'bad_issuer' ? '$authRoot/other' : authRoot,
            },
          );
          if (service != null) {
            await service.setForeground(false);
            expect(toolConnections.first.closed, true);
            expect(coordinator.isLoggingIn('notes'), true);
            callbacks.dispatch(callbackUri);
            await service!.setForeground(true);
            expect(coordinator.isLoggingIn('notes'), true);
          } else {
            await http.get(callbackUri);
          }
          if (scenario == 'bad_state') {
            coordinator.cancel('notes');
          }
        }

        if (scenario == 'background') {
          service = McpSettingsService(
            db,
            supportsStdio: false,
            oauthCallbacks: callbacks,
            openBrowser: openBrowser,
            connector: (_) async {
              final connection = FakeConnection();
              toolConnections.add(connection);
              return connection;
            },
          );
          coordinator = service.oauth;
          await service.initialized;
        } else {
          coordinator = McpOAuthCoordinator(
            db,
            callbacks,
            openBrowser: openBrowser,
          );
        }
        try {
          final config = McpServerConfig(
            name: 'notes',
            enabled: true,
            connection: McpHttpConfig(
              // Same endpoint, spelled differently from the normalized URIs
              // the metadata and stored token resource use.
              url: scenario == 'unnormalized_url'
                  ? 'HTTP://127.0.0.1:${server.port}/mcp'
                  : '$root/mcp',
              authMode: McpAuthMode.oauth,
              headers: {'X-Public-Setting': 'retain'},
              oauth: {
                if (scenario == 'manual_client') 'clientId': 'fixture-client',
              },
            ),
          );
          if (service != null) {
            await service.save(config, create: true);
            await service.activate();
            await service.runtime.ensureReady('notes');
          } else {
            await McpSettingsOrchestrator().save(
              database: db,
              config: config,
              create: true,
            );
          }
          if ([
            'bad_state',
            'bad_issuer',
            'cancel',
            'changed_config',
          ].contains(scenario)) {
            await expectLater(
              coordinator.login('notes'),
              throwsA(
                predicate(
                  (error) =>
                      [
                        'cancel',
                        'closed',
                        'issuer',
                        'unavailable',
                        'interrupted',
                      ].any(
                        (term) => error.toString().toLowerCase().contains(term),
                      ),
                ),
              ),
            );
            final saved =
                McpSettings.decode(
                      await db.appSettingsDao.get(McpSettings.key),
                    ).servers.single.connection
                    as McpHttpConfig;
            expect(saved.oauth.containsKey('accessToken'), false);
            expect(exchanges, 0);
            expect(coordinator.isLoggingIn('notes'), false);
            return;
          }
          await coordinator.login('notes');
          final saved = McpSettings.decode(
            await db.appSettingsDao.get(McpSettings.key),
          ).servers.single;
          final auth = (saved.connection as McpHttpConfig).oauth;
          expect(auth['accessToken'], 'access-1');
          expect(auth['issuer'], authRoot);
          expect(auth['resource'], rootResource ? root : '$root/mcp');
          expect(registrationCount, scenario == 'manual_client' ? 0 : 1);
          expect(exchanges, 1);
          // A registered client must not be stored as the user-configured
          // pre-registered client ID.
          expect(
            auth['clientId'],
            scenario == 'manual_client' ? 'fixture-client' : isNull,
          );
          expect(
            auth['registeredClientId'],
            scenario == 'manual_client' ? isNull : 'fixture-client',
          );
          expect(
            auth['registeredClientSecret'],
            confidential ? 'fixture-secret' : isNull,
          );
          if (scenario == 'persistence_failure') {
            await db.customStatement('PRAGMA query_only = ON');
            await expectLater(coordinator.tokens(saved), throwsA(anything));
            await db.customStatement('PRAGMA query_only = OFF');
            expect((await coordinator.tokens(saved))!.accessToken, 'access-2');
            expect(refreshes, 2);
            return;
          }
          if (scenario == 'refresh_unavailable') {
            await expectLater(
              coordinator.tokens(saved),
              throwsA(isNot(isA<McpNeedsAuth>())),
            );
            expect((await coordinator.tokens(saved))!.accessToken, 'access-2');
            expect(refreshes, 2);
            return;
          }
          if (scenario == 'refresh_revoked') {
            for (var attempt = 0; attempt < 2; attempt++) {
              await expectLater(
                coordinator.tokens(saved),
                throwsA(isA<McpNeedsAuth>()),
              );
            }
            expect(refreshes, 1);
            return;
          }
          if (scenario == 'login_cancelled_during_refresh') {
            Future<Object?>? relogin;
            beforeRefreshResponse = () async {
              beforeRefreshResponse = null;
              holdAuthorization = true;
              relogin = coordinator
                  .login('notes')
                  .then<Object?>((_) => null, onError: (Object error) => error);
              while (!coordinator.isLoggingIn('notes')) {
                await Future<void>.delayed(const Duration(milliseconds: 5));
              }
              coordinator.cancel('notes');
            };
            expect((await coordinator.tokens(saved))!.accessToken, 'access-2');
            expect(await relogin, isNotNull);
            final rotated =
                McpSettings.decode(
                      await db.appSettingsDao.get(McpSettings.key),
                    ).servers.single.connection
                    as McpHttpConfig;
            expect(rotated.oauth['accessToken'], 'access-2');
            expect(rotated.oauth['refreshToken'], 'refresh-2');
            expect(refreshes, 1);
            expect(exchanges, 1);
            return;
          }
          if (scenario == 'cancelled_refresh') {
            beforeRefreshResponse = () async {
              coordinator.invalidate('notes');
              await McpSettingsOrchestrator().save(
                database: db,
                config: saved.copyWith(enabled: false),
                create: false,
              );
              await McpSettingsOrchestrator().save(
                database: db,
                config: saved,
                create: false,
              );
              beforeRefreshResponse = null;
            };
            await expectLater(coordinator.tokens(saved), throwsA(anything));
            final retained =
                McpSettings.decode(
                      await db.appSettingsDao.get(McpSettings.key),
                    ).servers.single.connection
                    as McpHttpConfig;
            expect(retained.oauth['accessToken'], 'access-1');
            expect((await coordinator.tokens(saved))!.accessToken, 'access-2');
            expect(refreshes, 2);
            return;
          }
          if (scenario != 'no_refresh') {
            final tokens = await Future.wait([
              coordinator.tokens(saved),
              coordinator.tokens(saved),
            ]);
            expect(tokens.map((t) => t!.accessToken), ['access-2', 'access-2']);
            expect(refreshes, 1);
            expect((await coordinator.tokens(saved))!.accessToken, 'access-2');
            expect(refreshes, 1);
            final refreshed =
                McpSettings.decode(
                      await db.appSettingsDao.get(McpSettings.key),
                    ).servers.single.connection
                    as McpHttpConfig;
            expect(refreshed.oauth['refreshToken'], 'refresh-1');
          } else {
            expect((await coordinator.tokens(saved))!.accessToken, 'access-1');
            expect(refreshes, 0);
          }
          final logout = await coordinator.logout('notes');
          expect(logout.remoteFailed, scenario == 'revocation_failure');
          await expectLater(
            coordinator.tokens(saved),
            throwsA(isA<McpNeedsAuth>()),
          );
          final loggedOut =
              McpSettings.decode(
                    await db.appSettingsDao.get(McpSettings.key),
                  ).servers.single.connection
                  as McpHttpConfig;
          expect(loggedOut.oauth.containsKey('accessToken'), false);
          expect(loggedOut.oauth.containsKey('registeredClientSecret'), false);
          expect(loggedOut.headers, {'X-Public-Setting': 'retain'});
          if (confidential) {
            await coordinator.login('notes');
            expect(registrationCount, 2);
            expect(exchanges, 2);
          }
        } finally {
          await service?.close();
          await coordinator.close();
          await callbacks.close();
          await server.close(force: true);
          await authServer.close(force: true);
          await db.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
  for (final scenario in ['refreshed', 'refresh_revoked', 'rejected_again']) {
    test(
      'OAuth 401 without stored expiry refreshes once before login: $scenario',
      () async {
        final db = AppDatabase.forTest(NativeDatabase.memory());
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final root = 'http://127.0.0.1:${server.port}';
        var accepted = 'access-1';
        var refreshes = 0;
        var callsSent = 0;
        var callsRun = 0;
        server.listen((request) async {
          Object? body;
          switch (request.uri.path) {
            case '/mcp' when request.method != 'POST':
              request.response.statusCode = HttpStatus.methodNotAllowed;
            case '/mcp':
              final rpc =
                  jsonDecode(await utf8.decoder.bind(request).join())
                      as Map<String, dynamic>;
              if (rpc['method'] == 'tools/call') {
                callsSent++;
              }
              if (request.headers.value('authorization') !=
                  'Bearer $accepted') {
                request.response.statusCode = HttpStatus.unauthorized;
                request.response.headers.set('www-authenticate', 'Bearer');
              } else {
                if (rpc['method'] == 'tools/call') {
                  callsRun++;
                }
                body = reply(rpc);
                if (body == null) {
                  request.response.statusCode = HttpStatus.accepted;
                }
              }
            case '/.well-known/oauth-protected-resource/mcp':
              body = {
                'resource': '$root/mcp',
                'authorization_servers': [root],
              };
            case '/.well-known/oauth-authorization-server':
              body = {
                'issuer': root,
                'authorization_endpoint': '$root/authorize',
                'token_endpoint': '$root/token',
                'response_types_supported': ['code'],
                'code_challenge_methods_supported': ['S256'],
              };
            case '/token':
              final fields = Uri.splitQueryString(
                await utf8.decoder.bind(request).join(),
              );
              refreshes++;
              expect(fields['grant_type'], 'refresh_token');
              expect(fields['refresh_token'], 'refresh-1');
              if (scenario == 'refresh_revoked') {
                request.response.statusCode = HttpStatus.badRequest;
                body = {'error': 'invalid_grant'};
              } else {
                // No expires_in: the server decides when the token stops
                // working, so only its 401 can trigger the next refresh.
                body = {
                  'access_token': 'access-${refreshes + 1}',
                  'token_type': 'Bearer',
                };
              }
            default:
              request.response.statusCode = HttpStatus.notFound;
          }
          if (body != null) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(body));
          }
          await request.response.close();
        });
        await McpSettingsOrchestrator().save(
          database: db,
          config: McpServerConfig(
            name: 'notes',
            enabled: true,
            connection: McpHttpConfig(
              url: '$root/mcp',
              authMode: McpAuthMode.oauth,
              oauth: {
                'accessToken': 'access-1',
                'refreshToken': 'refresh-1',
                'issuer': root,
                'resource': '$root/mcp',
                'tokenEndpoint': '$root/token',
                'registeredClientId': 'fixture-client',
              },
            ),
          ),
          create: true,
        );
        var browserOpens = 0;
        final service = McpSettingsService(
          db,
          supportsStdio: false,
          openBrowser: (_) async {
            browserOpens++;
          },
        );
        Future<String?> storedAccess() async =>
            (McpSettings.decode(
                          await db.appSettingsDao.get(McpSettings.key),
                        ).servers.single.connection
                        as McpHttpConfig)
                    .oauth['accessToken']
                as String?;
        try {
          await service.initialized;
          await service.runtime.ensureReady('notes');
          // The server revokes the token early; the stored token still has
          // no expiry, so nothing refreshes it before the request.
          accepted = scenario == 'refreshed' ? 'access-2' : 'never-issued';
          final result = await McpToolDispatcher(
            service.runtime,
          ).call('mcp__notes__first', {});
          expect(browserOpens, 0);
          expect(refreshes, 1);
          if (scenario == 'refreshed') {
            expect(result.executionState, McpExecutionState.succeeded);
            expect(callsSent, 2);
            expect(callsRun, 1);
            expect(await storedAccess(), 'access-2');
            expect(
              service.runtime.states['notes']!.status,
              McpConnectionStatus.ready,
            );
            return;
          }
          expect(result.executionState, McpExecutionState.failed);
          expect(result.errorCode, 'mcp_needs_auth');
          expect(callsRun, 0);
          expect(callsSent, scenario == 'rejected_again' ? 2 : 1);
          expect(
            await storedAccess(),
            scenario == 'rejected_again' ? 'access-2' : 'access-1',
          );
          expect(
            service.runtime.states['notes']!.status,
            McpConnectionStatus.needs_auth,
          );
        } finally {
          await service.close();
          await server.close(force: true);
          await db.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  test(
    'OAuth connect rejected without stored expiry refreshes then connects',
    () async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final root = 'http://127.0.0.1:${server.port}';
      var refreshes = 0;
      server.listen((request) async {
        Object? body;
        switch (request.uri.path) {
          case '/mcp' when request.method != 'POST':
            request.response.statusCode = HttpStatus.methodNotAllowed;
          case '/mcp':
            final rpc =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            if (request.headers.value('authorization') != 'Bearer access-2') {
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.headers.set('www-authenticate', 'Bearer');
            } else {
              body = reply(rpc);
              if (body == null) {
                request.response.statusCode = HttpStatus.accepted;
              }
            }
          case '/.well-known/oauth-protected-resource/mcp':
            body = {
              'resource': '$root/mcp',
              'authorization_servers': [root],
            };
          case '/.well-known/oauth-authorization-server':
            body = {
              'issuer': root,
              'authorization_endpoint': '$root/authorize',
              'token_endpoint': '$root/token',
              'response_types_supported': ['code'],
              'code_challenge_methods_supported': ['S256'],
            };
          case '/token':
            refreshes++;
            body = {'access_token': 'access-2', 'token_type': 'Bearer'};
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        if (body != null) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
        }
        await request.response.close();
      });
      await McpSettingsOrchestrator().save(
        database: db,
        config: McpServerConfig(
          name: 'notes',
          enabled: true,
          connection: McpHttpConfig(
            url: '$root/mcp',
            authMode: McpAuthMode.oauth,
            oauth: {
              'accessToken': 'access-1',
              'refreshToken': 'refresh-1',
              'issuer': root,
              'resource': '$root/mcp',
              'tokenEndpoint': '$root/token',
              'registeredClientId': 'fixture-client',
            },
          ),
        ),
        create: true,
      );
      final service = McpSettingsService(
        db,
        supportsStdio: false,
        openBrowser: (_) async {},
      );
      try {
        await service.initialized;
        await service.runtime.ensureReady('notes');
        expect(refreshes, 1);
        expect(
          service.runtime.states['notes']!.status,
          McpConnectionStatus.ready,
        );
      } finally {
        await service.close();
        await server.close(force: true);
        await db.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
