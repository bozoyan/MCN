// 职责: 验证远端图片磁盘缓存的命中、原子写入残留回收与保留期/容量裁剪边界。
// 关联文件:
//   lib/shared/services/network_image/disk_cache.dart
//   lib/shared/utils/storage_paths.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/data-deletion.md

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/network_image/disk_cache.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;

  setUp(() async {
    tempSupport = await Directory.systemTemp.createTemp('reveric_img_cache_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempSupport.path;
            }
            return null;
          },
        );
    await RevericPaths.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  /// 直接在缓存目录里造一个条目，模拟「之前下载过」。
  Future<File> seed(
    String url, {
    required int bytes,
    DateTime? modified,
  }) async {
    final file = NetworkImageDiskCache.fileFor(url);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List(bytes));
    if (modified != null) {
      await file.setLastModified(modified);
    }
    return file;
  }

  group('NetworkImageDiskCache.fileFor', () {
    // 同一个 URL 必须稳定映射到同一个文件，否则每次启动都等于冷缓存。
    test('maps a url to a stable path and different urls apart', () {
      const url = 'https://cdn.example.com/cover/万妖图录传.jpg';
      expect(
        NetworkImageDiskCache.fileFor(url).path,
        NetworkImageDiskCache.fileFor(url).path,
      );
      expect(
        NetworkImageDiskCache.fileFor(url).path,
        isNot(NetworkImageDiskCache.fileFor('$url?v=2').path),
      );
      expect(
        p.dirname(NetworkImageDiskCache.fileFor(url).path),
        NetworkImageDiskCache.directory().path,
      );
    });
  });

  group('NetworkImageDiskCache.load', () {
    // 用户场景：昨天加载过图片，今天重开 app。期望直接读盘，不发请求。
    // 这里给一个必然连不通的地址：只要发起下载就会抛，能拿到字节就证明是命中。
    test('returns cached bytes without hitting the network', () async {
      const url = 'https://cdn.invalid.test/cover.jpg';
      await seed(url, bytes: 12);

      final bytes = await NetworkImageDiskCache.load(url);

      expect(bytes, hasLength(12));
    });

    // 写入被中断留下的空文件如果被当成命中，这张图会永久解码失败。
    test('discards an empty cache entry instead of returning it', () async {
      const url = 'https://cdn.invalid.test/empty.jpg';
      final file = await seed(url, bytes: 0);

      await expectLater(NetworkImageDiskCache.load(url), throwsA(anything));
      expect(await file.exists(), isFalse);
    });
  });

  group('NetworkImageDiskCache.prune', () {
    test('returns empty result when the cache was never created', () async {
      final result = await NetworkImageDiskCache.prune(cutoff: DateTime.now());

      expect(result.deletedFiles, 0);
      expect(result.freedBytes, 0);
    });

    // retention 的核心语义：早于 cutoff 的删，之后的留。
    test('deletes entries written before the cutoff only', () async {
      final now = DateTime.now();
      final stale = await seed(
        'https://cdn.example.com/old.jpg',
        bytes: 100,
        modified: now.subtract(const Duration(days: 40)),
      );
      final fresh = await seed(
        'https://cdn.example.com/new.jpg',
        bytes: 200,
        modified: now.subtract(const Duration(days: 1)),
      );

      final result = await NetworkImageDiskCache.prune(
        cutoff: now.subtract(const Duration(days: 30)),
      );

      expect(result.deletedFiles, 1);
      expect(result.freedBytes, 100);
      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    });

    // `.tmp` 是被中断的写入留下的，没有 rename 目标，再新也要回收。
    test('reclaims interrupted temp files regardless of age', () async {
      final root = NetworkImageDiskCache.directory();
      await root.create(recursive: true);
      final temp = File(p.join(root.path, 'abc123.w_deadbeef.tmp'));
      await temp.writeAsBytes(Uint8List(64));

      final result = await NetworkImageDiskCache.prune(
        cutoff: DateTime.now().subtract(const Duration(days: 30)),
      );

      expect(result.deletedFiles, 1);
      expect(result.freedBytes, 64);
      expect(await temp.exists(), isFalse);
    });

    // 容量兜底：即使全部都在保留期内，也要把总体积压回上限，先删最旧的。
    test('trims oldest survivors down to the size budget', () async {
      final now = DateTime.now();
      final oldest = await seed(
        'https://cdn.example.com/a.jpg',
        bytes: 400,
        modified: now.subtract(const Duration(days: 3)),
      );
      final middle = await seed(
        'https://cdn.example.com/b.jpg',
        bytes: 400,
        modified: now.subtract(const Duration(days: 2)),
      );
      final newest = await seed(
        'https://cdn.example.com/c.jpg',
        bytes: 400,
        modified: now.subtract(const Duration(days: 1)),
      );

      final result = await NetworkImageDiskCache.prune(
        cutoff: now.subtract(const Duration(days: 30)),
        maxBytes: 900,
      );

      expect(result.deletedFiles, 1);
      expect(result.freedBytes, 400);
      expect(await oldest.exists(), isFalse);
      expect(await middle.exists(), isTrue);
      expect(await newest.exists(), isTrue);
    });

    // 删除范围必须严格限定在缓存目录内，不能顺着 support 根往外扩。
    test('never touches files outside the cache directory', () async {
      final now = DateTime.now();
      final outsider = File(p.join(tempSupport.path, 'novel_covers.sqlite'));
      await outsider.writeAsBytes(Uint8List(10));
      await outsider.setLastModified(now.subtract(const Duration(days: 999)));
      await seed(
        'https://cdn.example.com/a.jpg',
        bytes: 10,
        modified: now.subtract(const Duration(days: 999)),
      );

      final result = await NetworkImageDiskCache.prune(
        cutoff: now.subtract(const Duration(days: 30)),
      );

      expect(result.deletedFiles, 1);
      expect(await outsider.exists(), isTrue);
    });
  });
}
