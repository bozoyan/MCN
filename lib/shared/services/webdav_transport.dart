// 职责: 通过 HTTP WebDAV 方法完成远程目录探测、文件枚举、上传与下载。
// 关联文件:
//   lib/shared/models/webdav_backup_config.dart
//   lib/shared/services/webdav_backup_service.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md

import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/webdav_backup_config.dart';

class WebDavCredentials {
  const WebDavCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

class WebDavTransportException implements Exception {
  const WebDavTransportException({required this.statusCode, this.message});

  final int? statusCode;
  final String? message;

  @override
  String toString() => 'WebDavTransportException(statusCode: $statusCode)';
}

class WebDavTransport {
  const WebDavTransport();

  Future<void> ensureDirectory({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
  }) async {
    final client = _createClient(credentials);
    try {
      final segments = config.remoteDirectory
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      for (var index = 1; index <= segments.length; index += 1) {
        final path = '/${segments.take(index).join('/')}';
        final response = await _send(
          client,
          method: 'MKCOL',
          uri: _remoteUri(config.serverUrl, path),
          credentials: credentials,
        );
        if (!_isSuccess(response.statusCode) && response.statusCode != 405) {
          final statusCode = response.statusCode;
          await _drain(response);
          throw WebDavTransportException(statusCode: statusCode);
        }
        await _drain(response);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<List<WebDavBackupFile>> listBackups({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
  }) async {
    final client = _createClient(credentials);
    try {
      final response = await _send(
        client,
        method: 'PROPFIND',
        uri: _remoteUri(config.serverUrl, config.remoteDirectory),
        credentials: credentials,
        headers: const <String, String>{'Depth': '1'},
        body: utf8.encode(_propertyRequestBody),
        contentType: 'application/xml; charset=utf-8',
      );
      if (response.statusCode != 207 && !_isSuccess(response.statusCode)) {
        final statusCode = response.statusCode;
        await _drain(response);
        throw WebDavTransportException(statusCode: statusCode);
      }
      final xmlText = await _readText(response, maxBytes: 8 * 1024 * 1024);
      return _parseBackupFiles(xmlText, config);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> upload({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
    required File localFile,
  }) async {
    final client = _createClient(credentials);
    try {
      // WebDAV Digest 认证的首次挑战不会保留 PUT 请求体，先用无请求体的
      // PROPFIND 完成认证，再发送文件流。
      final probe = await _send(
        client,
        method: 'PROPFIND',
        uri: _remoteUri(config.serverUrl, config.remoteDirectory),
        credentials: credentials,
        headers: const <String, String>{'Depth': '0'},
      );
      if (probe.statusCode != 207 && !_isSuccess(probe.statusCode)) {
        final statusCode = probe.statusCode;
        await _drain(probe);
        throw WebDavTransportException(statusCode: statusCode);
      }
      await _drain(probe);

      final stat = await localFile.stat();
      final response = await _send(
        client,
        method: 'PUT',
        uri: _remoteUri(
          config.serverUrl,
          '${config.remoteDirectory}/${_basename(localFile.path)}',
        ),
        credentials: credentials,
        contentLength: stat.size,
        stream: localFile.openRead(),
        contentType: 'application/zip',
      );
      if (!_isSuccess(response.statusCode)) {
        final statusCode = response.statusCode;
        await _drain(response);
        throw WebDavTransportException(statusCode: statusCode);
      }
      await _drain(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> download({
    required WebDavBackupConfig config,
    required WebDavCredentials credentials,
    required String remotePath,
    required File destination,
  }) async {
    final client = _createClient(credentials);
    IOSink? sink;
    try {
      final response = await _send(
        client,
        method: 'GET',
        uri: _remoteUri(config.serverUrl, remotePath),
        credentials: credentials,
      );
      if (!_isSuccess(response.statusCode)) {
        final statusCode = response.statusCode;
        await _drain(response);
        throw WebDavTransportException(statusCode: statusCode);
      }
      sink = destination.openWrite();
      await response.pipe(sink);
      sink = null;
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  HttpClient _createClient(WebDavCredentials credentials) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60);
    client.authenticate = (uri, scheme, realm) async {
      final credential = switch (scheme.toLowerCase()) {
        'digest' => HttpClientDigestCredentials(
          credentials.username,
          credentials.password,
        ),
        _ => HttpClientBasicCredentials(
          credentials.username,
          credentials.password,
        ),
      };
      client.addCredentials(uri, realm ?? '', credential);
      return true;
    };
    return client;
  }

  Future<HttpClientResponse> _send(
    HttpClient client, {
    required String method,
    required Uri uri,
    required WebDavCredentials credentials,
    Map<String, String> headers = const <String, String>{},
    List<int>? body,
    Stream<List<int>>? stream,
    int? contentLength,
    String? contentType,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
    );
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (contentLength != null) {
      request.contentLength = contentLength;
    } else if (body != null) {
      request.contentLength = body.length;
    }
    if (body != null) {
      request.add(body);
    }
    if (stream != null) {
      await request.addStream(stream);
    }
    return request.close();
  }
}

Uri _remoteUri(String serverUrl, String remotePath) {
  final base = Uri.parse(serverUrl);
  final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
  final remoteSegments = remotePath
      .split('/')
      .where((segment) => segment.isNotEmpty);
  return base.replace(
    pathSegments: <String>[...baseSegments, ...remoteSegments],
    query: null,
    fragment: null,
  );
}

List<WebDavBackupFile> _parseBackupFiles(
  String xmlText,
  WebDavBackupConfig config,
) {
  final document = XmlDocument.parse(xmlText);
  final files = <WebDavBackupFile>[];
  for (final response in document.findAllElements(
    'response',
    namespaceUri: '*',
  )) {
    final href = response
        .findAllElements('href', namespaceUri: '*')
        .firstOrNull
        ?.innerText;
    if (href == null || href.isEmpty) {
      continue;
    }
    final decodedPath = Uri.decodeComponent(Uri.parse(href).path);
    final name = decodedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    if (name == null ||
        !name.startsWith('reveric_backup_') ||
        !name.endsWith('.zip')) {
      continue;
    }
    final sizeText = response
        .findAllElements('getcontentlength', namespaceUri: '*')
        .firstOrNull
        ?.innerText;
    final modifiedText = response
        .findAllElements('getlastmodified', namespaceUri: '*')
        .firstOrNull
        ?.innerText;
    files.add(
      WebDavBackupFile(
        name: name,
        remotePath: '${config.remoteDirectory}/$name',
        size: int.tryParse(sizeText ?? ''),
        modifiedAt: _tryParseHttpDate(modifiedText),
      ),
    );
  }
  files.sort((left, right) {
    final byDate = (right.modifiedAt ?? DateTime(0)).compareTo(
      left.modifiedAt ?? DateTime(0),
    );
    return byDate != 0 ? byDate : right.name.compareTo(left.name);
  });
  return files;
}

Future<String> _readText(
  HttpClientResponse response, {
  required int maxBytes,
}) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const WebDavTransportException(
        statusCode: null,
        message: 'Response exceeded size limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> _drain(HttpClientResponse response) => response.drain<void>();

bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

DateTime? _tryParseHttpDate(String? value) {
  if (value == null) return null;
  try {
    return HttpDate.parse(value).toLocal();
  } on FormatException {
    return null;
  }
}

const _propertyRequestBody = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getcontentlength />
    <d:getlastmodified />
    <d:resourcetype />
  </d:prop>
</d:propfind>''';
