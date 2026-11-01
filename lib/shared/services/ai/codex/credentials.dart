// 职责: 读取本机 Codex 登录态，在过期前刷新并安全写回凭据。
// 关联文件:
//   lib/shared/agent/client/codex_client.dart
//   lib/shared/widgets/settings/codex_connection.dart
//   lib/shared/logger/app_logger.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../logger/app_logger.dart';

final _log = AppLogger.forModule('CodexCredentials');
final _tokenUrl = Uri.parse('https://auth.openai.com/oauth/token');
const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';

enum CodexAuthFailure {
  unsupported_platform,
  missing,
  invalid,
  expired,
  refresh_failed,
  write_failed,
  changed,
}

class CodexAuthException implements Exception {
  const CodexAuthException(this.reason, {this.statusCode});
  final CodexAuthFailure reason;
  final int? statusCode;

  @override
  String toString() => 'CodexAuthException(${reason.name}, HTTP $statusCode)';
}

class CodexCredentials {
  const CodexCredentials({required this.accessToken, required this.accountId});

  final String accessToken;
  final String accountId;

  static bool get supportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  // 合并同一进程中的并发刷新；每轮完成后移除，后续请求重新读取文件。
  static final _pending = <String, Future<CodexCredentials>>{};

  static Future<CodexCredentials> load({
    String? userHome,
    http.Client? client,
    DateTime? now,
  }) async {
    if (!supportedPlatform) {
      throw const CodexAuthException(CodexAuthFailure.unsupported_platform);
    }
    final home =
        userHome ??
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null || home.isEmpty) {
      throw const CodexAuthException(CodexAuthFailure.missing);
    }
    final path = p.normalize(p.absolute(home, '.codex', 'auth.json'));
    final pending = _pending[path];
    if (pending != null) {
      return pending;
    }
    final request = _load(File(path), client, now);
    _pending[path] = request;
    try {
      return await request;
    } finally {
      _pending.remove(path);
    }
  }

  static CodexCredentials parse(String source, {DateTime? now}) {
    final auth = _AuthDocument.parse(source);
    auth.checkExpiry(now ?? DateTime.now());
    return auth.credentials;
  }

  static Future<CodexCredentials> _load(
    File file,
    http.Client? client,
    DateTime? now,
  ) async {
    final source = await _read(file);
    final auth = _AuthDocument.parse(source);
    final expiresAt = auth.expiresAt;
    if (expiresAt == null ||
        expiresAt.isAfter(
          (now ?? DateTime.now()).add(const Duration(minutes: 5)),
        )) {
      return auth.credentials;
    }
    final refreshToken = auth.tokens['refresh_token'];
    if (refreshToken is! String || refreshToken.trim().isEmpty) {
      throw const CodexAuthException(CodexAuthFailure.expired);
    }
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            _tokenUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'client_id': _clientId,
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'scope': 'openid profile email',
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        _log.warning('refresh POST $_tokenUrl HTTP ${response.statusCode}');
        throw CodexAuthException(
          response.statusCode == 400 || response.statusCode == 401
              ? CodexAuthFailure.expired
              : CodexAuthFailure.refresh_failed,
          statusCode: response.statusCode,
        );
      }
      final fresh = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = fresh['access_token'] as String;
      if (accessToken.trim().isEmpty) {
        throw const FormatException();
      }
      auth.tokens['access_token'] = accessToken;
      for (final key in ['id_token', 'refresh_token']) {
        final value = fresh[key] as String?;
        if (value != null && value.trim().isNotEmpty) {
          auth.tokens[key] = value;
        }
      }
      auth.raw['last_refresh'] = (now ?? DateTime.now())
          .toUtc()
          .toIso8601String();
      // 校验完整的新凭据之后才替换文件，错误响应不能破坏原登录态。
      parse(jsonEncode(auth.raw), now: now);
    } on CodexAuthException catch (error, stack) {
      if (error.statusCode != null) {
        rethrow;
      }
      _logFailure('validate refreshed credentials', error, stack);
      throw const CodexAuthException(CodexAuthFailure.refresh_failed);
    } catch (error, stack) {
      _logFailure('refresh POST $_tokenUrl', error, stack);
      throw const CodexAuthException(CodexAuthFailure.refresh_failed);
    } finally {
      if (client == null) {
        transport.close();
      }
    }
    await _save(file, source, auth.raw);
    return auth.credentials;
  }

  static Future<String> _read(File file) async {
    try {
      if (!await file.exists()) {
        throw const CodexAuthException(CodexAuthFailure.missing);
      }
      return await file.readAsString();
    } on FileSystemException catch (error, stack) {
      _logFailure('read auth.json', error, stack);
      throw const CodexAuthException(CodexAuthFailure.invalid);
    }
  }

  static Future<void> _save(
    File file,
    String source,
    Map<String, dynamic> raw,
  ) async {
    Directory? staging;
    try {
      // 同一文件系统上的 rename 才能原子替换，避免截断原文件。
      staging = await file.parent.createTemp('.reveric-auth-');
      final candidate = File(p.join(staging.path, 'auth.json'));
      await candidate.create();
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', candidate.path]);
        if (result.exitCode != 0) {
          throw const FileSystemException('credential permissions');
        }
      }
      await candidate.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
        flush: true,
      );
      // Codex 不共享本进程的锁；检测刷新期间的登录切换或外部刷新。
      if (await _read(file) != source) {
        throw const CodexAuthException(CodexAuthFailure.changed);
      }
      await candidate.rename(file.path);
    } on CodexAuthException {
      rethrow;
    } catch (error, stack) {
      _logFailure('write auth.json', error, stack);
      throw const CodexAuthException(CodexAuthFailure.write_failed);
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } catch (error, stack) {
          _logFailure('clean credential staging', error, stack);
        }
      }
    }
  }
}

void _logFailure(String stage, Object error, StackTrace stack) {
  // 原异常和响应体可能包含 token、文件正文或路径，只记录类型与阶段。
  _log.error('$stage failed (${error.runtimeType})', stackTrace: stack);
}

class _AuthDocument {
  _AuthDocument(this.raw);

  final Map<String, dynamic> raw;
  Map<String, dynamic> get tokens => raw['tokens'] as Map<String, dynamic>;

  static _AuthDocument parse(String source) {
    try {
      final auth = _AuthDocument(jsonDecode(source) as Map<String, dynamic>);
      if (auth.raw['auth_mode'] != null && auth.raw['auth_mode'] != 'chatgpt') {
        throw const FormatException();
      }
      auth.credentials;
      auth.expiresAt;
      return auth;
    } catch (_) {
      throw const CodexAuthException(CodexAuthFailure.invalid);
    }
  }

  CodexCredentials get credentials {
    final token = tokens['access_token'] as String;
    var accountId = tokens['account_id'] as String?;
    for (final key in ['id_token', 'access_token']) {
      if (accountId != null && accountId.trim().isNotEmpty) {
        break;
      }
      final claims = _claims(tokens[key] as String?);
      final auth =
          claims['https://api.openai.com/auth'] as Map<String, dynamic>?;
      accountId = auth?['chatgpt_account_id'] as String?;
    }
    if (token.trim().isEmpty || accountId == null || accountId.trim().isEmpty) {
      throw const FormatException();
    }
    return CodexCredentials(accessToken: token, accountId: accountId);
  }

  DateTime? get expiresAt {
    final expiry = _claims(tokens['access_token'] as String)['exp'] as num?;
    return expiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (expiry * 1000).toInt(),
            isUtc: true,
          );
  }

  void checkExpiry(DateTime now) {
    final expiry = expiresAt;
    if (expiry != null && !expiry.isAfter(now)) {
      throw const CodexAuthException(CodexAuthFailure.expired);
    }
  }

  static Map<String, dynamic> _claims(String? token) {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) {
      return {};
    }
    return jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        )
        as Map<String, dynamic>;
  }
}
