// 职责: S3 兼容对象存储的最小客户端 — AWS SigV4 签名的 HEAD / PUT / GET 与预签名下载链接。
// 关联文件:
//   lib/shared/models/object_storage_config.dart
//   lib/shared/services/object_storage/service.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/object_storage_config.dart';

/// 不签名请求体时的 `x-amz-content-sha256` 取值。
const s3UnsignedPayload = 'UNSIGNED-PAYLOAD';

/// 服务端返回非 2xx 时抛出；[code] 取自 S3 XML 错误体的 `<Code>`。
class S3Exception implements Exception {
  const S3Exception(this.statusCode, {this.code, this.body = ''});

  final int statusCode;
  final String? code;
  final String body;

  @override
  String toString() => 'S3Exception($statusCode, $code): $body';
}

class S3Client {
  S3Client(this.config, this.client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// 已规范化且校验通过的配置。
  final ObjectStorageConfig config;
  final http.Client client;
  final DateTime Function() _now;

  /// 对象存在时返回 true；404 / 403（无 ListBucket 权限时 S3 对不存在的对象回 403）返回 false。
  Future<bool> exists(String key) async {
    final response = await _send('HEAD', key, payloadHash: _emptyHash);
    if (response.statusCode == HttpStatus.ok) {
      return true;
    }
    if (response.statusCode == HttpStatus.notFound ||
        response.statusCode == HttpStatus.forbidden) {
      return false;
    }
    throw S3Exception(response.statusCode, body: response.body);
  }

  /// 上传文件；[sha256] 为文件内容的十六进制摘要，同时用作签名的 payload hash。
  Future<void> putFile(
    String key,
    File file, {
    required String sha256,
    required String contentType,
    required int length,
  }) async {
    final response = await _send(
      'PUT',
      key,
      payloadHash: sha256,
      contentType: contentType,
      contentLength: length,
      body: file.openRead(),
    );
    _check(response);
  }

  Future<void> putBytes(
    String key,
    List<int> bytes, {
    required String contentType,
  }) async {
    final response = await _send(
      'PUT',
      key,
      payloadHash: sha256.convert(bytes).toString(),
      contentType: contentType,
      contentLength: bytes.length,
      body: Stream.value(bytes),
    );
    _check(response);
  }

  /// 生成带签名的 GET 链接，S3 允许的最长有效期为 7 天。
  Uri presignGet(String key, Duration expires) {
    final time = _now().toUtc();
    final uri = objectUri(key);
    final scope = _scope(time);
    final query = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '${config.accessKeyId}/$scope',
      'X-Amz-Date': _amzDate(time),
      'X-Amz-Expires': '${expires.inSeconds}',
      'X-Amz-SignedHeaders': 'host',
    };
    final canonicalQuery = _canonicalQuery(query);
    final canonical = [
      'GET',
      uri.path,
      canonicalQuery,
      'host:${_host(uri)}\n',
      'host',
      s3UnsignedPayload,
    ].join('\n');
    final signature = _signature(time, canonical);
    return uri.replace(query: '$canonicalQuery&X-Amz-Signature=$signature');
  }

  /// 对象的直接地址；path 已按 S3 规则逐段编码。
  Uri objectUri(String key) {
    final endpoint = Uri.parse(config.endpoint);
    final basePath = endpoint.path.endsWith('/')
        ? endpoint.path.substring(0, endpoint.path.length - 1)
        : endpoint.path;
    final encodedKey = encodeS3Key(key);
    if (config.pathStyle) {
      return endpoint.replace(
        path: '$basePath/${_encode(config.bucket)}/$encodedKey',
      );
    }
    return endpoint.replace(
      host: '${config.bucket}.${endpoint.host}',
      path: '$basePath/$encodedKey',
    );
  }

  Future<http.Response> _send(
    String method,
    String key, {
    required String payloadHash,
    String? contentType,
    int? contentLength,
    Stream<List<int>>? body,
  }) async {
    final time = _now().toUtc();
    final uri = objectUri(key);
    final headers = <String, String>{
      'host': _host(uri),
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': _amzDate(time),
    };
    final signedHeaders = headers.keys.toList()..sort();
    final canonical = [
      method,
      uri.path,
      '',
      for (final name in signedHeaders) '$name:${headers[name]}',
      '',
      signedHeaders.join(';'),
      payloadHash,
    ].join('\n');
    final request = _S3Request(method, uri, body ?? const Stream.empty())
      ..headers['x-amz-content-sha256'] = payloadHash
      ..headers['x-amz-date'] = headers['x-amz-date']!
      ..headers['authorization'] =
          'AWS4-HMAC-SHA256 '
          'Credential=${config.accessKeyId}/${_scope(time)}, '
          'SignedHeaders=${signedHeaders.join(';')}, '
          'Signature=${_signature(time, canonical)}';
    if (contentType != null) {
      request.headers['content-type'] = contentType;
    }
    request.contentLength = contentLength ?? 0;
    return http.Response.fromStream(await client.send(request));
  }

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final code = RegExp(
      r'<Code>([^<]+)</Code>',
    ).firstMatch(response.body)?.group(1);
    throw S3Exception(response.statusCode, code: code, body: response.body);
  }

  String _scope(DateTime time) =>
      '${_amzDate(time).substring(0, 8)}/${config.region}/s3/aws4_request';

  String _signature(DateTime time, String canonicalRequest) {
    final date = _amzDate(time).substring(0, 8);
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      _amzDate(time),
      _scope(time),
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    List<int> key = utf8.encode('AWS4${config.secretAccessKey}');
    for (final part in [date, config.region, 's3', 'aws4_request']) {
      key = Hmac(sha256, key).convert(utf8.encode(part)).bytes;
    }
    return Hmac(sha256, key).convert(utf8.encode(stringToSign)).toString();
  }
}

/// 请求体在发送时才开始读取，连接失败不会把整个文件读进内存。
class _S3Request extends http.BaseRequest {
  _S3Request(super.method, super.url, this._body);

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

/// 按 S3 规则逐段编码对象 key，保留 `/`。
String encodeS3Key(String key) => key.split('/').map(_encode).join('/');

final _emptyHash = sha256.convert(const <int>[]).toString();

String _host(Uri uri) => uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

String _amzDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}${two(time.month)}'
      '${two(time.day)}T${two(time.hour)}${two(time.minute)}'
      '${two(time.second)}Z';
}

String _canonicalQuery(Map<String, String> query) {
  final keys = query.keys.toList()..sort();
  return keys.map((key) => '${_encode(key)}=${_encode(query[key]!)}').join('&');
}

/// RFC 3986 编码：只保留 unreserved 字符。
String _encode(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final char = String.fromCharCode(byte);
    if (RegExp(r'[A-Za-z0-9\-._~]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}
