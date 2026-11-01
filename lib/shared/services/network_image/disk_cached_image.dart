// 职责: 带磁盘缓存的网络图片 ImageProvider — 命中本地字节解码，未命中下载后落盘。
// 关联文件:
//   lib/shared/services/network_image/disk_cache.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'disk_cache.dart';

/// 字节来自 [NetworkImageDiskCache] 的网络图片。
///
/// 与 `Image.network` 的唯一区别是字节从磁盘缓存取，不是每次重新请求。内存层
/// 仍然是 Flutter 自己的 `ImageCache`：同一个 key 的并发请求由它合流，所以这里
/// 不需要再维护一份 in-flight 表 —— 前提是 [operator ==] / [hashCode] 准确，
/// 漏掉任何一个字段都会退化成「每个 widget 各下一遍」。
///
/// [decodeWidth] 限制解码后位图的宽度（设备像素），高度按原图比例缩放。注意它
/// 参与 key：同一张图传不同值会各自解码、各占一份内存，所以同类场景要共用同一
/// 个常量，不要按实际布局宽度逐处计算。
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {this.scale = 1.0, this.decodeWidth});

  final String url;
  final double scale;
  final int? decodeWidth;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DiskCachedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        ErrorDescription('URL: ${key.url}'),
      ],
    );
  }

  Future<ui.Codec> _loadCodec(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await NetworkImageDiskCache.load(key.url);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final width = key.decodeWidth;
      if (width == null) {
        return await decode(buffer);
      }
      return await decode(
        buffer,
        // 只给 width，高度由引擎按原图比例推导；原图比目标还小就别放大。
        getTargetSize: (intrinsicWidth, _) => ui.TargetImageSize(
          width: intrinsicWidth < width ? intrinsicWidth : width,
        ),
      );
    } catch (_) {
      // 失败的 key 必须踢出 ImageCache：否则这次错误会被记住，重建也不再触发
      // 下载，表现为封面永久停在占位图直到重启。
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage &&
      other.url == url &&
      other.scale == scale &&
      other.decodeWidth == decodeWidth;

  @override
  int get hashCode => Object.hash(url, scale, decodeWidth);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DiskCachedImage')}("$url", '
      'scale: $scale, decodeWidth: $decodeWidth)';
}
