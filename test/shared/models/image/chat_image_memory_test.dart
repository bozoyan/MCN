// 职责: 验证聊天出图参数记忆的 JSON 往返、空值归一与损坏输入的行为。
// 关联文件:
//   lib/shared/models/image/chat_image_memory.dart
//   lib/shared/models/image/extras.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/image/chat_image_memory.dart';
import 'package:reveric/shared/models/image/extras.dart';

void main() {
  group('聊天出图参数记忆', () {
    test('JSON 往返保持全部字段', () {
      const memory = ChatImageMemoryData(
        modelOptionId: 'modelscope::Qwen/Qwen-Image-2.1-Turbo',
        size: '1024x1024',
        extras: ImageRequestExtras(
          loras: [ModelScopeLora(repoId: 'bozoyan/Q-FEIFEI', weight: 1)],
          steps: 8,
          guidance: 1.0,
          seed: -1,
        ),
      );
      final restored = ChatImageMemoryData.decode(memory.encode());
      expect(restored.modelOptionId, memory.modelOptionId);
      expect(restored.size, memory.size);
      expect(restored.extras?.loras.single.repoId, 'bozoyan/Q-FEIFEI');
      expect(restored.extras?.loras.single.weight, 1);
      expect(restored.extras?.steps, 8);
      expect(restored.extras?.guidance, 1.0);
      expect(restored.extras?.seed, -1);
    });

    test('MOSS 扩展参数往返保持开关与负向词', () {
      const memory = ChatImageMemoryData(
        modelOptionId: 'moss::moss-image-sft-1.0',
        size: '768x1024',
        extras: ImageRequestExtras(
          negativePrompt: 'blurry',
          promptEnhance: true,
          outputWatermark: false,
        ),
      );
      final restored = ChatImageMemoryData.decode(memory.encode());
      expect(restored.extras?.negativePrompt, 'blurry');
      expect(restored.extras?.promptEnhance, true);
      expect(restored.extras?.outputWatermark, false);
    });

    test('空记忆编解码后各字段为空', () {
      final restored = ChatImageMemoryData.decode(
        ChatImageMemoryData.defaults.encode(),
      );
      expect(restored.modelOptionId, isNull);
      expect(restored.size, isNull);
      expect(restored.extras, isNull);
    });

    test('空 extras 归一为 null 后不再落库', () {
      // 对话框保存侧把 isEmpty 的 extras 归一为 null,这里验证该语义:
      // extras 为 null 时 encode 不含 extras 键。
      final json = ChatImageMemoryData(
        modelOptionId: 'modelscope::Qwen/Qwen-Image-2.1',
      ).toJson();
      expect(json.containsKey('extras'), isFalse);
    });

    test('损坏 JSON 抛 FormatException,由读取侧回落默认', () {
      expect(() => ChatImageMemoryData.decode('not-json'), throwsFormatException);
      expect(
        () => ChatImageMemoryData.decode('["array"]'),
        throwsFormatException,
      );
    });
  });
}
