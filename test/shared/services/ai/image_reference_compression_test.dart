// 职责: 验证参考图按需压缩 — 阈值内保留原图、超限缩放降质、解码失败上报
// 关联文件:
//   lib/shared/services/ai/image_reference_compression.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reveric/shared/services/ai/image_reference_compression.dart';

void main() {
  test('compresses and downscales an oversized reference', () {
    final sourceBytes = Uint8List.fromList(
      img.encodePng(_noisyImage(width: 2200, height: 1600)),
    );
    expect(sourceBytes.length, greaterThan(imageReferenceMaxBytes));

    final result = compressImageReference(
      ImageReferenceCompressionRequest(bytes: sourceBytes, extension: 'png'),
    );

    expect(result.decodeFailed, isFalse);
    expect(result.extension, 'jpg');
    expect(result.bytes.length, lessThan(imageReferenceMaxBytes));
    // 长边压到上限，短边等比缩。
    final compressed = img.decodeImage(result.bytes)!;
    expect(compressed.width, imageReferenceMaxDimension);
    expect(
      compressed.height,
      (1600 * imageReferenceMaxDimension / 2200).round(),
    );
  });

  test('downscales a portrait reference on its long edge', () {
    final sourceBytes = Uint8List.fromList(
      img.encodePng(_noisyImage(width: 1600, height: 2200)),
    );

    final result = compressImageReference(
      ImageReferenceCompressionRequest(bytes: sourceBytes, extension: 'png'),
    );

    final compressed = img.decodeImage(result.bytes)!;
    expect(compressed.height, imageReferenceMaxDimension);
    expect(
      compressed.width,
      (1600 * imageReferenceMaxDimension / 2200).round(),
    );
  });

  test('keeps a small reference untouched instead of re-encoding it', () {
    // 纯色小图：转 JPEG 只会变大又掉画质，必须原样发出。
    final source = img.Image(width: 512, height: 512);
    for (final pixel in source) {
      pixel
        ..r = 200
        ..g = 210
        ..b = 220;
    }
    final sourceBytes = Uint8List.fromList(img.encodePng(source));
    expect(sourceBytes.length, lessThan(imageReferenceMaxBytes));

    final result = compressImageReference(
      ImageReferenceCompressionRequest(bytes: sourceBytes, extension: 'png'),
    );

    expect(result.extension, 'png');
    expect(result.bytes, same(sourceBytes));
  });

  test('reports decode failure without throwing', () {
    final result = compressImageReference(
      ImageReferenceCompressionRequest(
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        extension: 'png',
      ),
    );

    expect(result.decodeFailed, isTrue);
    expect(result.extension, 'png');
    expect(result.bytes.length, 5);
  });
}

/// 伪随机噪声图：纯色图 PNG 压得太狠，撑不到体积阈值以上。
img.Image _noisyImage({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  var state = 0x12345678;
  for (final pixel in image) {
    state = (state * 1664525 + 1013904223) & 0x7fffffff;
    pixel
      ..r = state & 0xff
      ..g = (state >> 8) & 0xff
      ..b = (state >> 16) & 0xff;
  }
  return image;
}
