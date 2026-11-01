// 职责: 验证图片生成错误分类能认出余额不足（402 / credit.insufficient）与参考图超限。
// 关联文件:
//   lib/shared/services/ai/image.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/image.dart';

void main() {
  test('classifyAiImageError recognizes credit exhaustion phrases', () {
    expect(
      classifyAiImageError('insufficient credit'),
      AiImageErrorCode.credit,
    );
    expect(
      classifyAiImageError('credit.insufficient'),
      AiImageErrorCode.credit,
    );
    expect(
      classifyAiImageError('type=insufficient_quota'),
      AiImageErrorCode.credit,
    );
  });

  test('classifyAiImageError recognizes provider model denial', () {
    // 供应商 403 的 message 与 code 都要认得出，否则 403 会落到「检查 API Key」。
    expect(
      classifyAiImageError('model forbidden for user'),
      AiImageErrorCode.model_forbidden,
    );
    expect(
      classifyAiImageError('model.forbidden'),
      AiImageErrorCode.model_forbidden,
    );
  });

  test('classifyAiImageError recognizes oversized reference file', () {
    // 魔搭参考图超 5MB 的真实报错:含 "file size" 而非出图尺寸,
    // 不得被通用 size 判定误分类成「图片尺寸不受支持」。
    expect(
      classifyAiImageError('image file size exceed limit: 5242880'),
      AiImageErrorCode.file_too_large,
    );
    expect(
      classifyAiImageError('File Too Large'),
      AiImageErrorCode.file_too_large,
    );
  });

  test('classifyAiImageError still maps pixel-size violations to size', () {
    expect(
      classifyAiImageError(
        'size requires dimensions 256..2048 divisible by 16, '
        'at most 2097152 pixels',
      ),
      AiImageErrorCode.size,
    );
  });
}
