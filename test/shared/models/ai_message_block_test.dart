// 职责: AI 消息块模型测试 — 验证思考块 signature 与图片资产 ID 的序列化保留
// 关联文件:
//   lib/shared/models/ai_message_block.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_message_block.dart';

void main() {
  test('image asset survives patching and chat history serialization', () {
    const original = AiImageBlock(id: 'image', prompt: 'portrait');
    final updated = original.copyWith(
      assetId: 'asset-1',
      localFilePath: 'images/a.png',
      status: AiImageStatus.success,
    );
    final restored = AiMessageBlock.fromJson(updated.toJson()) as AiImageBlock;
    expect(restored.assetId, 'asset-1');
    expect(restored.copyWith(prompt: 'edited').assetId, 'asset-1');
    expect(
      (AiMessageBlock.fromJson(original.toJson()) as AiImageBlock).assetId,
      isNull,
    );
  });
  group('AiThinkingBlock', () {
    test('serializes and restores signature and encrypted contents', () {
      const block = AiThinkingBlock(
        id: 'thinking_1',
        text: 'reasoning',
        signature: 'sig123',
        encryptedContents: ['enc_a', 'enc_b'],
      );

      final json = block.toJson();
      expect(json['kind'], 'thinking');
      expect(json['text'], 'reasoning');
      expect(json['signature'], 'sig123');
      expect(json['encryptedContents'], ['enc_a', 'enc_b']);

      final restored = AiMessageBlock.fromJson(json);
      expect(restored, isA<AiThinkingBlock>());
      final thinking = restored as AiThinkingBlock;
      expect(thinking.text, 'reasoning');
      expect(thinking.signature, 'sig123');
      expect(thinking.encryptedContents, ['enc_a', 'enc_b']);
    });
  });
}
