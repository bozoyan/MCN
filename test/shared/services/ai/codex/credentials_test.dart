// 职责: 验证 Codex 登录态解析、并发刷新、安全写回及失败边界。
// 关联文件:
//   lib/shared/services/ai/codex/credentials.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/services/ai/codex/credentials.dart';

String _jwt(Map<String, dynamic> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';
String _auth(String token, {String? accountId, String? idToken}) => jsonEncode({
  'tokens': {
    'access_token': token,
    'account_id': accountId,
    'id_token': ?idToken,
  },
});

void main() {
  final now = DateTime.utc(2026, 10, 5);
  String expiringToken(Duration remaining) =>
      _jwt({'exp': now.add(remaining).millisecondsSinceEpoch ~/ 1000});
  late Directory home;
  late File file;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('reveric-codex-test-');
    final directory = await Directory('${home.path}/.codex').create();
    file = File('${directory.path}/auth.json');
  });
  tearDown(() => home.delete(recursive: true));

  Future<String> seed({Duration remaining = const Duration(minutes: 5)}) async {
    final source = jsonEncode({
      'auth_mode': 'chatgpt',
      'OPENAI_API_KEY': null,
      'custom': {'keep': true},
      'tokens': {
        'access_token': expiringToken(remaining),
        'refresh_token': 'refresh-secret',
        'id_token': _jwt({
          'https://api.openai.com/auth': {'chatgpt_account_id': 'id-account'},
        }),
        'other': 'keep',
      },
    });
    await file.writeAsString(source);
    return source;
  }

  Future<CodexCredentials> load(http.Client client) =>
      CodexCredentials.load(userHome: home.path, client: client, now: now);

  Matcher failure(CodexAuthFailure reason) => throwsA(
    isA<CodexAuthException>().having((e) => e.reason, 'reason', reason),
  );

  test('uses ID token before access token and accepts an empty account ID', () {
    final access = _jwt({
      'https://api.openai.com/auth': {'chatgpt_account_id': 'access-account'},
    });
    final id = _jwt({
      'https://api.openai.com/auth': {'chatgpt_account_id': 'id-account'},
    });
    expect(
      CodexCredentials.parse(_auth(access, idToken: id)).accountId,
      'id-account',
    );
    expect(
      CodexCredentials.parse(
        _auth(access, idToken: id, accountId: ''),
      ).accountId,
      'id-account',
    );
    expect(
      CodexCredentials.parse(
        _auth(access, idToken: id, accountId: 'explicit'),
      ).accountId,
      'explicit',
    );
  });

  test('reads explicit account ID and JWT account claim', () {
    final token = _jwt({
      'https://api.openai.com/auth': {'chatgpt_account_id': 'claim-account'},
    });
    expect(CodexCredentials.parse(_auth(token)).accountId, 'claim-account');
    expect(
      CodexCredentials.parse(_auth(token, accountId: 'selected')).accountId,
      'selected',
    );
  });

  test('rejects expired tokens', () {
    expect(
      () => CodexCredentials.parse(
        _auth(_jwt({'exp': 10}), accountId: 'account'),
        now: DateTime.fromMillisecondsSinceEpoch(10000),
      ),
      throwsA(
        isA<CodexAuthException>().having(
          (e) => e.reason,
          'reason',
          CodexAuthFailure.expired,
        ),
      ),
    );
  });

  test(
    'API-key-only and malformed files are rejected without exposing contents',
    () {
      for (final source in [
        '{"OPENAI_API_KEY":"secret"}',
        '{"auth_mode":"apikey","tokens":{"access_token":"secret","account_id":"account"}}',
        'secret invalid json',
        _auth('secret'),
        _auth('', accountId: 'account'),
      ]) {
        try {
          CodexCredentials.parse(source);
          fail('expected invalid credentials');
        } on CodexAuthException catch (error) {
          expect(error.reason, CodexAuthFailure.invalid);
          expect(error.toString(), isNot(contains('secret')));
        }
      }
    },
  );

  test('rereads changed auth files without modifying them', () async {
    await file.writeAsString(_auth('first', accountId: 'account'));
    expect(
      (await CodexCredentials.load(userHome: home.path)).accessToken,
      'first',
    );
    final updated = _auth('second', accountId: 'account');
    await file.writeAsString(updated);
    expect(
      (await CodexCredentials.load(userHome: home.path)).accessToken,
      'second',
    );
    expect(await file.readAsString(), updated);
  });

  test('missing auth file has an actionable failure type', () async {
    // 只认用户主目录下的 .codex/auth.json，不把主目录本身当作 Codex 目录。
    await File(
      '${home.path}/auth.json',
    ).writeAsString(_auth('token', accountId: 'account'));
    await expectLater(
      CodexCredentials.load(userHome: home.path),
      throwsA(
        isA<CodexAuthException>().having(
          (e) => e.reason,
          'reason',
          CodexAuthFailure.missing,
        ),
      ),
    );
  });

  test(
    'valid token beyond refresh window does not contact OAuth or write',
    () async {
      final source = await seed(remaining: const Duration(minutes: 6));
      final client = MockClient(
        (_) async => throw StateError('must not request'),
      );
      addTearDown(client.close);
      expect((await load(client)).accountId, 'id-account');
      expect(await file.readAsString(), source);
    },
  );

  for (final remaining in [
    const Duration(minutes: 5),
    const Duration(minutes: -1),
  ]) {
    test('refreshes at $remaining and preserves unrelated fields', () async {
      await seed(remaining: remaining);
      final next = expiringToken(const Duration(hours: 1));
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://auth.openai.com/oauth/token');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'client_id': 'app_EMoamEEZ73f0CkXaXp7hrann',
          'grant_type': 'refresh_token',
          'refresh_token': 'refresh-secret',
          'scope': 'openid profile email',
        });
        return http.Response(
          jsonEncode({
            'access_token': next,
            'refresh_token': 'rotated-secret',
            'id_token': _jwt({
              'https://api.openai.com/auth': {
                'chatgpt_account_id': 'new-id-account',
              },
            }),
          }),
          200,
        );
      });
      addTearDown(client.close);
      final credentials = await load(client);
      expect(credentials.accessToken, next);
      expect(credentials.accountId, 'new-id-account');
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved['tokens']['refresh_token'], 'rotated-secret');
      expect(saved['tokens']['other'], 'keep');
      expect(saved['custom'], {'keep': true});
      expect(saved['OPENAI_API_KEY'], isNull);
      expect(DateTime.parse(saved['last_refresh']), now);
      expect(await file.parent.list().length, 1);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      }
    });
  }

  test('omitted optional tokens survive refresh and reload', () async {
    final source = jsonDecode(await seed()) as Map;
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode({'access_token': expiringToken(const Duration(hours: 1))}),
        200,
      );
    });
    addTearDown(client.close);
    await load(client);
    await load(client);
    final saved = jsonDecode(await file.readAsString()) as Map;
    for (final key in ['id_token', 'refresh_token']) {
      expect(saved['tokens'][key], source['tokens'][key]);
    }
    expect(requests, 1);
  });

  test('concurrent callers share one refresh and rotated token', () async {
    await seed();
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var requests = 0;
    final client = MockClient((_) {
      requests++;
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final first = load(client);
    await started.future;
    final second = load(client);
    response.complete(
      http.Response(
        jsonEncode({
          'access_token': expiringToken(const Duration(hours: 1)),
          'refresh_token': 'rotated-secret',
        }),
        200,
      ),
    );
    final credentials = await Future.wait([first, second]);
    expect(requests, 1);
    expect(credentials[0].accessToken, credentials[1].accessToken);
    expect(
      jsonDecode(await file.readAsString())['tokens']['refresh_token'],
      'rotated-secret',
    );
  });

  test('cannot refresh without a refresh token', () async {
    final source = _auth(expiringToken(Duration.zero), accountId: 'account');
    await file.writeAsString(source);
    final client = MockClient(
      (_) async => throw StateError('must not request'),
    );
    addTearDown(client.close);
    await expectLater(load(client), failure(CodexAuthFailure.expired));
    expect(await file.readAsString(), source);
  });

  for (final status in [400, 401, 403, 429, 500]) {
    test(
      'OAuth $status preserves the file and exposes only safe error details',
      () async {
        final source = await seed();
        final client = MockClient(
          (_) async => http.Response('refresh-secret echoed', status),
        );
        addTearDown(client.close);
        await expectLater(
          load(client),
          throwsA(
            isA<CodexAuthException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  status == 400 || status == 401
                      ? CodexAuthFailure.expired
                      : CodexAuthFailure.refresh_failed,
                )
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.toString(),
                  'safe message',
                  isNot(contains('secret')),
                ),
          ),
        );
        expect(await file.readAsString(), source);
      },
    );
  }

  for (final body in [
    'secret invalid json',
    '{}',
    '{"access_token":""}',
    '{"access_token":42}',
    jsonEncode({'access_token': expiringToken(Duration.zero)}),
    jsonEncode({'access_token': 'malformed.secret.jwt'}),
    jsonEncode({'access_token': 'new-token', 'id_token': 42}),
  ]) {
    test(
      'invalid OAuth response $body does not overwrite credentials',
      () async {
        final source = await seed();
        final client = MockClient((_) async => http.Response(body, 200));
        addTearDown(client.close);
        await expectLater(
          load(client),
          failure(CodexAuthFailure.refresh_failed),
        );
        expect(await file.readAsString(), source);
      },
    );
  }

  test(
    'network failure releases pending refresh so a retry can succeed',
    () async {
      final source = await seed();
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        if (requests == 1) {
          throw http.ClientException('refresh-secret');
        }
        return http.Response(
          jsonEncode({'access_token': expiringToken(const Duration(hours: 1))}),
          200,
        );
      });
      addTearDown(client.close);
      await expectLater(load(client), failure(CodexAuthFailure.refresh_failed));
      expect(await file.readAsString(), source);
      expect((await load(client)).accountId, 'id-account');
      expect(requests, 2);
    },
  );

  test(
    'does not overwrite login changed by another process during refresh',
    () async {
      await seed();
      final changed = _auth('external-token', accountId: 'external-account');
      final client = MockClient((_) async {
        await file.writeAsString(changed);
        return http.Response(
          jsonEncode({'access_token': expiringToken(const Duration(hours: 1))}),
          200,
        );
      });
      addTearDown(client.close);
      await expectLater(load(client), failure(CodexAuthFailure.changed));
      expect(await file.readAsString(), changed);
      expect(await file.parent.list().length, 1);
      expect((await load(client)).accountId, 'external-account');
    },
  );

  test(
    'write failure is explicit and leaves the original auth intact',
    () async {
      final source = await seed();
      final client = MockClient((_) async {
        final result = await Process.run('chmod', ['500', file.parent.path]);
        expect(result.exitCode, 0);
        return http.Response(
          jsonEncode({'access_token': expiringToken(const Duration(hours: 1))}),
          200,
        );
      });
      addTearDown(client.close);
      try {
        await expectLater(load(client), failure(CodexAuthFailure.write_failed));
        expect(await file.readAsString(), source);
      } finally {
        await Process.run('chmod', ['700', file.parent.path]);
      }
    },
    skip: Platform.isWindows,
  );
}
