// 职责: 按固定版本与 SHA-256 准备本地深度模型，支持取消及原子安装。
// 关联文件:
//   lib/shared/services/depth/model.dart
//   lib/shared/services/production/ffmpeg_runner.dart
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:socks5_proxy/exceptions.dart';
import '../production/ffmpeg_runner.dart';
import '../editing/disk_space.dart';
import 'model.dart';
import '../../logger/app_logger.dart';

final _log = AppLogger.forModule('Depth');

class DepthModelService {
  DepthModelService(
    this.directory,
    this.manifest, {
    this.freeBytes = editingFreeBytes,
    this.createClient = HttpClient.new,
  });
  final FutureOr<HttpClient> Function() createClient;
  final int Function(String directory) freeBytes;
  final Directory directory;
  final DepthModelManifest manifest;
  File get file => File(p.join(directory.path, '${manifest.version}.onnx'));
  bool _preparing = false;

  Future<bool> isReady(MediaCancellation token) async {
    checkDepthCancellation(token);
    if (!await file.exists() || await file.length() != manifest.bytes) {
      return false;
    }
    final digest = await crypto.sha256
        .bind(
          file.openRead().map((chunk) {
            checkDepthCancellation(token);
            return chunk;
          }),
        )
        .first;
    checkDepthCancellation(token);
    return digest.toString() == manifest.sha256;
  }

  Future<File> prepare(MediaCancellation token, DepthProgress progress) async {
    if (_preparing) {
      throw StateError('Depth model preparation is already active');
    }
    _preparing = true;
    HttpClient? client;
    Directory? temporary;
    try {
      progress(DepthStage.preparing, null);
      if (await isReady(token)) {
        return file;
      }
      if (manifest.source.isEmpty) {
        throw const DepthException(DepthFailure.model_source);
      }
      await directory.create(recursive: true);
      if (freeBytes(directory.path) < manifest.bytes + 64 * 1024 * 1024) {
        throw const DepthException(DepthFailure.insufficient_space);
      }
      temporary = await directory.createTemp('.install-');
      final part = File(p.join(temporary.path, 'model.part'));
      final uri = Uri.tryParse(manifest.source);
      Stream<List<int>> input;
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        // HTTP is limited to loopback test fixtures. Production sources use TLS.
        if (uri.scheme == 'http' &&
            !['localhost', '127.0.0.1', '::1'].contains(uri.host)) {
          throw const DepthException(DepthFailure.model_source);
        }
        progress(DepthStage.connecting, null);
        client = await createClient();
        client.connectionTimeout = const Duration(seconds: 30);
        checkDepthCancellation(token);
        await token.bind(() async => client?.close(force: true));
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 30));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        _log.info(
          'model response host=${uri.host} status=${response.statusCode}',
        );
        if (response.statusCode != 200 ||
            (response.contentLength >= 0 &&
                response.contentLength != manifest.bytes)) {
          throw const DepthException(DepthFailure.model_source);
        }
        progress(DepthStage.downloading, 0);
        input = response.timeout(const Duration(seconds: 30));
      } else {
        input = File(manifest.source).openRead();
      }
      final output = await part.open(mode: FileMode.write);
      var received = 0;
      try {
        await for (final chunk in input) {
          checkDepthCancellation(token);
          received += chunk.length;
          if (received > manifest.bytes) {
            throw const DepthException(DepthFailure.model_invalid);
          }
          await output.writeFrom(chunk);
          progress(DepthStage.downloading, received / manifest.bytes);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      checkDepthCancellation(token);
      progress(DepthStage.verifying, null);
      final hash = await crypto.sha256
          .bind(
            part.openRead().map((chunk) {
              checkDepthCancellation(token);
              return chunk;
            }),
          )
          .first;
      if (received != manifest.bytes || hash.toString() != manifest.sha256) {
        throw const DepthException(DepthFailure.model_invalid);
      }
      checkDepthCancellation(token);
      // Keep the old file until verification succeeds; Windows rename cannot
      // replace an existing destination. The retired copy belongs to this temp.
      if (await file.exists()) {
        await file.rename(p.join(temporary.path, 'previous.onnx'));
      }
      await part.rename(file.path);
      return file;
    } catch (error, stack) {
      checkDepthCancellation(token);
      if (error is SocketException ||
          error is HttpException ||
          error is TlsException ||
          error is SocksClientException ||
          error is TimeoutException) {
        _log.error(
          'model download failed host=${Uri.tryParse(manifest.source)?.host} type=${error.runtimeType}',
          error: error.toString().replaceAll(RegExp(r'https?://\S+'), '<url>'),
          stackTrace: stack,
        );
        throw const DepthException(DepthFailure.model_source);
      }
      rethrow;
    } finally {
      token.unbind();
      client?.close(force: true);
      _preparing = false;
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }
}
