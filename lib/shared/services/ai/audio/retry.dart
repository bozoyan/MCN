// 职责: 对音频只读请求的瞬时网络故障执行有限退避重试，并记录脱敏诊断。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/exception.dart
//   lib/shared/services/ai/media_diagnostics.dart
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../logger/app_logger.dart';
import '../../../models/audio/exception.dart';
import '../media_diagnostics.dart';

final _log = AppLogger.forModule('AudioRead');

bool retryableAudioRead(Object error) {
  if (error is http.RequestAbortedException) {
    return false;
  }
  if (error is AudioException) {
    final status = error.statusCode;
    return status == 429 || (status != null && status >= 500 && status <= 599);
  }
  return error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException ||
      error is http.ClientException;
}

Future<T> retryAudioRead<T>(
  Future<T> Function(int attempt) operation, {
  required String context,
  String apiKey = '',
  Future<void>? abortTrigger,
  Duration delay = const Duration(seconds: 1),
}) async {
  var cancelled = false;
  if (abortTrigger != null) {
    unawaited(abortTrigger.then((_) => cancelled = true));
  }
  for (var attempt = 1; ; attempt++) {
    await Future<void>.value();
    if (cancelled) {
      throw const AudioException('cancelled');
    }
    try {
      return await operation(attempt);
    } catch (error) {
      if (cancelled || error is AudioException && error.code == 'cancelled') {
        throw const AudioException('cancelled');
      }
      final retry = attempt < 3 && retryableAudioRead(error);
      final wait = delay * attempt;
      _log.warning(
        '$context attempt=$attempt/3 retry=$retry '
        'delay_ms=${retry ? wait.inMilliseconds : 0} '
        'type=${error.runtimeType} '
        'status=${error is AudioException ? error.statusCode : null} '
        'error=${safeMediaDiagnostic(error, apiKey)} '
        'detail=${error is AudioException ? safeMediaDiagnostic(error.detail ?? "", apiKey) : ""}',
      );
      if (!retry) {
        rethrow;
      }
      final ready = Completer<void>();
      final timer = Timer(wait, ready.complete);
      try {
        await Future.any([ready.future, ?abortTrigger]);
      } finally {
        timer.cancel();
      }
    }
  }
}
