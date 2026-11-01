// 职责: 参考图上传前的按需压缩 — 纯计算，可在 isolate 中执行，决定是否缩放/重编码
// 关联文件:
//   lib/shared/services/ai/image.dart
//   lib/shared/services/map_place_name_reader.dart

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 超过这个体积才考虑重编码。小图重编码通常只会掉画质：实测 512x512 纯色 PNG
/// 1.8KB，转 JPEG q50 反而涨到 4.7KB。
const imageReferenceMaxBytes = 3 * 1024 * 1024;

/// 长边上限。超过就先等比缩到这个尺寸，再谈质量。
const imageReferenceMaxDimension = 2048;

/// 逐档降质，直到落进 [imageReferenceMaxBytes]。最低到 40 就不再降 —— 再低
/// 画面细节已经不足以当参考图用了，宁可发一张偏大的。
const imageReferenceQualitySteps = <int>[80, 65, 50, 40];

class ImageReferenceCompressionRequest {
  const ImageReferenceCompressionRequest({
    required this.bytes,
    required this.extension,
    this.hardMaxBytes,
  });

  final Uint8List bytes;

  /// 原始扩展名（`png` / `jpg`）。不压缩时原样带回。
  final String extension;

  /// 可选的严格体积上限。为空时保持参考图原有策略；非空时最低质量仍超限会继续缩图。
  final int? hardMaxBytes;
}

class ImageReferenceCompressionResult {
  const ImageReferenceCompressionResult({
    required this.bytes,
    required this.extension,
    required this.logLine,
    this.decodeFailed = false,
  });

  final Uint8List bytes;
  final String extension;

  /// 交给调用方写进 app 日志的一行；这里不能碰 logger（isolate 里没有它的上下文）。
  final String logLine;

  /// 解码失败：调用方据此报「文件非法」。此时 [bytes] 仍是原始字节。
  final bool decodeFailed;
}

/// 只在「确有必要」时重编码：
/// 1. 体积和尺寸都在阈值内 → 原样返回，不动画质；
/// 2. 需要处理 → 先缩到长边上限，再逐档降质直到达标；
/// 3. 压完反而比原图大 → 退回原图；调用方给出严格上限时则继续缩图到上限内。
///
/// 带 alpha 的图目前也会转 JPEG（透明区被填成白底），这是已知取舍。
ImageReferenceCompressionResult compressImageReference(
  ImageReferenceCompressionRequest request,
) {
  final source = request.bytes;
  final originalBytes = source.length;
  final maxBytes = request.hardMaxBytes ?? imageReferenceMaxBytes;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return ImageReferenceCompressionResult(
      bytes: source,
      extension: request.extension,
      decodeFailed: true,
      logLine:
          'reference_decode_failed original_bytes=$originalBytes '
          'extension=${request.extension}',
    );
  }

  final oversized = originalBytes > maxBytes;
  final tooLarge =
      decoded.width > imageReferenceMaxDimension ||
      decoded.height > imageReferenceMaxDimension;
  if (!oversized && !tooLarge) {
    return ImageReferenceCompressionResult(
      bytes: source,
      extension: request.extension,
      logLine:
          'reference_kept original_bytes=$originalBytes '
          'dimensions=${decoded.width}x${decoded.height}',
    );
  }

  var working = decoded;
  if (tooLarge) {
    final landscape = working.width >= working.height;
    working = img.copyResize(
      working,
      width: landscape ? imageReferenceMaxDimension : null,
      height: landscape ? null : imageReferenceMaxDimension,
      interpolation: img.Interpolation.linear,
    );
  }

  var encoded = img.encodeJpg(
    working,
    quality: imageReferenceQualitySteps.first,
    chroma: img.JpegChroma.yuv420,
  );
  var quality = imageReferenceQualitySteps.first;
  for (final step in imageReferenceQualitySteps.skip(1)) {
    if (encoded.length <= maxBytes) {
      break;
    }
    quality = step;
    encoded = img.encodeJpg(
      working,
      quality: step,
      chroma: img.JpegChroma.yuv420,
    );
  }

  if (request.hardMaxBytes != null) {
    while (encoded.length > maxBytes &&
        (working.width > 512 || working.height > 512)) {
      final landscape = working.width >= working.height;
      final longEdge = landscape ? working.width : working.height;
      var nextLongEdge = (longEdge * 4) ~/ 5;
      if (nextLongEdge < 512) {
        nextLongEdge = 512;
      }
      if (nextLongEdge >= longEdge) {
        break;
      }
      working = img.copyResize(
        working,
        width: landscape ? nextLongEdge : null,
        height: landscape ? null : nextLongEdge,
        interpolation: img.Interpolation.linear,
      );
      quality = imageReferenceQualitySteps.last;
      encoded = img.encodeJpg(
        working,
        quality: quality,
        chroma: img.JpegChroma.yuv420,
      );
    }
  }

  // 缩放过就必须用新图（原图尺寸超限），否则压完变大时退回原图更划算。
  if (!tooLarge && encoded.length >= originalBytes) {
    return ImageReferenceCompressionResult(
      bytes: source,
      extension: request.extension,
      logLine:
          'reference_kept_larger_when_compressed original_bytes=$originalBytes '
          'compressed_bytes=${encoded.length} quality=$quality',
    );
  }

  return ImageReferenceCompressionResult(
    bytes: encoded,
    extension: 'jpg',
    logLine:
        'reference_compressed original_bytes=$originalBytes '
        'compressed_bytes=${encoded.length} '
        'ratio=${(encoded.length / originalBytes).toStringAsFixed(3)} '
        'quality=$quality dimensions=${working.width}x${working.height}',
  );
}
