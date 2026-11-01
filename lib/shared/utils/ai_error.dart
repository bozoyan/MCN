// 职责: 从 AI SDK 异常和 HTTP 响应中提取状态码、供应商错误码及消息。
// 关联文件:
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/agent/client.dart
//   lib/shared/services/ai/video/client.dart
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/ai/image/client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' show ClientException;

/// SDK 异常通过 statusCode 暴露状态码；不从自由文本猜测。
int? tryReadStatusCode(Object error) {
  try {
    final statusCode = (error as dynamic).statusCode;
    if (statusCode is num) {
      return statusCode.toInt();
    }
  } on Object {
    return null;
  }
  return null;
}

String? tryReadProviderErrorCode(Object error) => _read(error, code: true);

/// 提取供应商原始 message，排除本地异常、完整 JSON 和 HTML 包装。
String? tryReadProviderMessage(Object error) => _read(error, code: false);

String? _read(Object error, {required bool code}) {
  if (error is IOException ||
      error is ClientException ||
      error is TimeoutException ||
      error is FormatException ||
      error is Error) {
    return null;
  }
  if (error is Map || error is String) {
    return _extract(error, code: code, depth: 0);
  }
  final dynamic provider = error;
  for (final read in <Object? Function()>[
    () => provider.body,
    () => provider.message,
    if (code) () => {'code': provider.code},
  ]) {
    try {
      final result = _extract(read(), code: code, depth: 0);
      if (result != null) {
        return result;
      }
    } on NoSuchMethodError {
      // 不同 SDK 暴露不同属性，缺失属性不参与解析。
    }
  }
  return null;
}

final _codePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,127}$');
final _httpPrefix = RegExp(r'^HTTP \d{3}:\s*');

String? _extract(Object? value, {required bool code, required int depth}) {
  if (depth >= 8) {
    return null;
  }
  if (value is Map) {
    // 中转响应可能在 metadata.raw 中保留上游错误，外层 code 只是 HTTP 状态。
    for (final nested in [
      value['error'],
      value['Error'],
      value['ResponseMetadata'],
      value['metadata'],
      value['raw'],
      if (value['data'] is Map) value['data'],
      if (value['output'] is Map) value['output'],
      if (value['task'] is Map) value['task'],
    ]) {
      final result = _extract(nested, code: code, depth: depth + 1);
      if (result != null) {
        return result;
      }
    }
    if (code) {
      final candidate = value['code'] ?? value['Code'];
      if (candidate is String && _codePattern.hasMatch(candidate.trim())) {
        return candidate.trim();
      }
    }
    return _extract(
      value['message'] ??
          value['Message'] ??
          value['error_message'] ??
          value['msg'],
      code: code,
      depth: depth + 1,
    );
  }
  if (value is! String) {
    return null;
  }
  var message = value.trim();
  final sse = message.startsWith('data:');
  if (sse) {
    message = message.substring(5).trim();
  }
  message = message.replaceFirst(_httpPrefix, '');
  if (sse || message.startsWith('{') || message.startsWith('[')) {
    try {
      return _extract(jsonDecode(message), code: code, depth: depth + 1);
    } on FormatException {
      return null;
    }
  }
  if (code ||
      message.isEmpty ||
      message.startsWith('<') ||
      const {
        'unknown error',
        'unknown api error',
        'openai_error',
      }.contains(message.toLowerCase())) {
    return null;
  }
  return message;
}
