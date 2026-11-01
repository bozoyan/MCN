// 职责: 远端图片磁盘缓存 — 按 URL 摘要落盘、原子写入，并按保留期与容量裁剪。
// 关联文件:
//   lib/shared/services/network_image/disk_cached_image.dart
//   lib/shared/services/storage_cleanup_service.dart
//   lib/shared/utils/storage_paths.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/file-access.md
//   .agents/rules/data-deletion.md

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../logger/app_logger.dart';
import '../../utils/random_id.dart';
import '../../utils/storage_paths.dart';

final _log = AppLogger.forModule('NetworkImageCache');

/// 磁盘缓存不可用或远端返回不可解码内容时抛出。
///
/// 独立类型的意义在于：调用方能把「这张图拿不到」和真正的 IO 异常区分开，
/// 不用去匹配 `http` / `dart:io` 的异常字符串。
class NetworkImageCacheException implements Exception {
  const NetworkImageCacheException(this.message);

  final String message;

  @override
  String toString() => 'NetworkImageCacheException: $message';
}

/// 一轮裁剪的结果。
class NetworkImageCachePruneResult {
  const NetworkImageCachePruneResult({
    this.deletedFiles = 0,
    this.freedBytes = 0,
  });

  final int deletedFiles;
  final int freedBytes;

  @override
  String toString() => 'files=$deletedFiles bytes=$freedBytes';
}

/// 远端图片的磁盘缓存。
///
/// 只服务「URL 稳定、无鉴权、同一 URL 内容不变」的图片：命中磁盘
/// 即直接使用，不做 ETag / Last-Modified 重验证。需要重验证、带鉴权或会原地
/// 替换内容的图片不要走这里，它们会一直拿到第一次下载的那一版。
///
/// 目录 `<ApplicationSupport>/network_image_cache/`，文件名取 URL 的 SHA-1。
/// 写入先落临时文件再 rename：下载中断只会留下一个 `.tmp`，不会留下一张能被
/// 永久命中的半图。
class NetworkImageDiskCache {
  NetworkImageDiskCache._();

  static const String directoryName = 'network_image_cache';

  /// 容量上限。超出后按最后写入时间从旧到新删，直到回到上限以内。
  static const int maxTotalBytes = 128 << 20;

  static const String _tempSuffix = '.tmp';

  /// 缓存根目录。依赖 [RevericPaths] 已完成初始化（启动期保证）。
  static Directory directory() =>
      Directory(p.join(RevericPaths.supportRoot, directoryName));

  static File fileFor(String url) =>
      File(p.join(directory().path, sha1.convert(utf8.encode(url)).toString()));

  /// 取 [url] 的图片字节：命中磁盘直接返回，否则下载并落盘。
  ///
  /// 下载失败、非 200、空响应体一律抛 [NetworkImageCacheException] 且不写盘 ——
  /// 失败结果不能进缓存，否则一次网络抖动会让这张图永久停在占位图。
  static Future<Uint8List> load(String url) async {
    final file = fileFor(url);
    final cached = await _read(file, url);
    if (cached != null) {
      return cached;
    }
    final bytes = await _download(url);
    await _write(file, bytes, url);
    return bytes;
  }

  /// 读磁盘副本；未命中返回 null。
  static Future<Uint8List?> _read(File file, String url) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        return bytes;
      }
      // 空文件只可能来自异常中断；留着会让这张图永远解码失败，删掉重下。
      _log.warning('cache entry empty, refetching url=$url');
      await file.delete();
      return null;
    } on FileSystemException catch (error, stackTrace) {
      // 读缓存失败不阻断下载，但必须留痕：否则「每次都在重下」无从察觉。
      _log.error(
        'cache read failed url=$url name=${p.basename(file.path)}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<Uint8List> _download(String url) async {
    final http.Response response;
    try {
      response = await http.get(Uri.parse(url));
    } catch (error) {
      // 不带堆栈：断网时一屏封面就是几十上百次同样的失败，堆栈只会把日志冲满，
      // 而「哪个 URL、什么异常」已经足够定位。堆栈留给写盘/读盘那类真异常。
      _log.warning(
        'cache fetch failed url=$url type=${error.runtimeType} error=$error',
      );
      rethrow;
    }
    if (response.statusCode != 200) {
      _log.warning(
        'cache fetch rejected url=$url status=${response.statusCode} '
        'bytes=${response.bodyBytes.length}',
      );
      throw NetworkImageCacheException(
        'HTTP ${response.statusCode} while fetching $url',
      );
    }
    if (response.bodyBytes.isEmpty) {
      _log.warning('cache fetch empty url=$url status=200');
      throw NetworkImageCacheException('Empty response body for $url');
    }
    return response.bodyBytes;
  }

  /// 原子落盘：先写唯一临时文件，成功后再 rename 到目标名。
  ///
  /// 写失败不往上抛 —— 字节已经在调用方手里，这一次显示不受影响，下次再下一遍
  /// 即可；但失败会记 error 日志，不会变成一个看不见的持续退化。
  static Future<void> _write(File file, Uint8List bytes, String url) async {
    final temp = File(
      '${file.path}.${buildRandomId('w', length: 8)}$_tempSuffix',
    );
    try {
      await file.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } catch (error, stackTrace) {
      _log.error(
        'cache write failed url=$url bytes=${bytes.length}',
        error: error,
        stackTrace: stackTrace,
      );
      await _delete(temp, missingIsFine: true);
    }
  }

  /// 裁剪缓存目录：先删早于 [cutoff] 的条目，再把总体积压回 [maxBytes] 以内。
  ///
  /// 删除范围严格限定为 [directory] 下由本类写入的文件，以及自己留下的 `.tmp`
  /// 残留；不递归子目录，不触碰任何其他路径。这些文件全部可以按原 URL 重新
  /// 下载，删掉只是让下次显示多一次网络请求。
  ///
  /// 时间基准是文件最后写入时间（即下载时间），不是最后命中时间：命中不回写
  /// mtime，省掉每次命中一次 syscall，代价是常用图到期后会重下一次。
  static Future<NetworkImageCachePruneResult> prune({
    required DateTime cutoff,
    int maxBytes = maxTotalBytes,
  }) async {
    final root = directory();
    if (!await root.exists()) {
      return const NetworkImageCachePruneResult();
    }

    final survivors = <({File file, DateTime modified, int size})>[];
    var deletedFiles = 0;
    var freedBytes = 0;

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      // `.tmp` 没有对应的 rename 目标，只可能是被中断的写入，直接回收。
      final expendable =
          entity.path.endsWith(_tempSuffix) || stat.modified.isBefore(cutoff);
      if (expendable) {
        if (await _delete(entity)) {
          deletedFiles++;
          freedBytes += stat.size;
        }
        continue;
      }
      survivors.add((file: entity, modified: stat.modified, size: stat.size));
    }

    var total = survivors.fold<int>(0, (sum, entry) => sum + entry.size);
    if (total > maxBytes) {
      survivors.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in survivors) {
        if (total <= maxBytes) {
          break;
        }
        if (await _delete(entry.file)) {
          deletedFiles++;
          freedBytes += entry.size;
          total -= entry.size;
        }
      }
    }

    if (deletedFiles > 0) {
      _log.info(
        'prune removed files=$deletedFiles bytes=$freedBytes '
        'cutoff=${cutoff.toIso8601String()} remaining=$total',
      );
    }
    return NetworkImageCachePruneResult(
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
    );
  }

  static Future<bool> _delete(File file, {bool missingIsFine = false}) async {
    try {
      if (missingIsFine && !await file.exists()) {
        return false;
      }
      await file.delete();
      return true;
    } on FileSystemException catch (error, stackTrace) {
      _log.error(
        'cache delete failed name=${p.basename(file.path)}',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
