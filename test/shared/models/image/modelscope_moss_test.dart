// 职责: 验证魔搭与 MOSS 渠道的预设、能力约束及请求级扩展参数的校验与序列化。
// 关联文件:
//   lib/shared/models/image/catalog.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/models/image/extras.dart
//   lib/shared/models/ai_provider.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/image/channels.dart';
import 'package:reveric/shared/models/image/extras.dart';
import 'package:reveric/shared/models/production/image_request.dart';
import 'package:reveric/shared/services/ai/image/moss.dart';
import '../../../helpers/media_provider_types.dart';

void main() {
  group('魔搭渠道', () {
    test('预设清单为魔搭托管的七个底座模型', () {
      expect(imageModelsForProvider('modelscope'), [
        'Qwen/Qwen-Image-2.1-Turbo',
        'Qwen/Qwen-Image-2.1',
        'Tongyi-MAI/Z-Image-Turbo',
        'krea/Krea-2-Turbo',
        'MusePublic/flux-high-res',
        'openmoss/MOSS-Image-SFT',
        'briaai/Fibo-2.0-dev',
      ]);
    });

    test('渠道命中与制作规格校验', () {
      final channel = lookupImageChannelModel(
        imageProviderType(ImageProtocol.modelscope_image),
        'Qwen/Qwen-Image-2.1-Turbo',
      );
      expect(channel, isNotNull);
      expect(channel!.catalogId, 'qwen-image-2.1-turbo');
      expect(channel.protocolOptions, isA<ModelScopeImageOptions>());

      final provider = aiProviderBuiltinById('modelscope')!.copyWith(
        id: 'ms-custom',
        enabled: true,
      );
      ProductionImageCapabilities(provider, 'Qwen/Qwen-Image-2.1-Turbo')
          .validate(
        prompt: 'cover',
        ratio: '1:1',
        resolution: '2K',
        references: 0,
      );
    });

    test('固定 Base URL 指向 API-Inference 域名', () {
      expect(
        aiProviderFixedBaseUrl(AiProviderType.modelscope),
        'https://api-inference.modelscope.cn',
      );
    });

    test('建议步数只对官方登记的两个 Qwen 底座给出', () {
      // 文档:Turbo 步数 8,Qwen-Image-2.1 步数 50;其他底座不猜值。
      expect(
        modelScopeRecommendedSteps('Qwen/Qwen-Image-2.1-Turbo'),
        8,
      );
      expect(modelScopeRecommendedSteps('Qwen/Qwen-Image-2.1'), 50);
      expect(modelScopeRecommendedSteps('Tongyi-MAI/Z-Image-Turbo'), isNull);
      expect(modelScopeRecommendedSteps(''), isNull);
    });
  });

  group('MOSS 渠道', () {
    test('预设清单与尺寸表约束', () {
      expect(imageModelsForProvider('moss'), [
        'moss-image-sft-1.0',
        'moss-image-base-1.0',
      ]);
      final channel = lookupImageChannelModel(
        imageProviderType(ImageProtocol.moss_image),
        'moss-image-sft-1.0',
      );
      expect(channel, isNotNull);
      final caps = channel!.capabilities;
      // 所有档位尺寸每边 256-2048、16 的倍数,总像素不超过服务端上限 2097152。
      for (final sizes in caps.sizes.values) {
        for (final size in sizes.values) {
          final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(size)!;
          final width = int.parse(match[1]!);
          final height = int.parse(match[2]!);
          expect(width % 16, 0, reason: size);
          expect(height % 16, 0, reason: size);
          expect(width, greaterThanOrEqualTo(256), reason: size);
          expect(height, greaterThanOrEqualTo(256), reason: size);
          expect(width, lessThanOrEqualTo(2048), reason: size);
          expect(height, lessThanOrEqualTo(2048), reason: size);
          expect(width * height, lessThanOrEqualTo(2097152), reason: size);
        }
      }
    });

    test('制作规格:合法档位通过、未登记比例拒绝', () {
      final provider = aiProviderBuiltinById('moss')!.copyWith(
        id: 'moss-custom',
        enabled: true,
      );
      final caps = ProductionImageCapabilities(provider, 'moss-image-sft-1.0');
      caps.validate(
        prompt: 'cover',
        ratio: '1:1',
        resolution: '2K',
        references: 0,
      );
      expect(
        () => caps.validate(
          prompt: 'cover',
          ratio: '4:1',
          resolution: '2K',
          references: 0,
        ),
        throwsFormatException,
      );
      // 纯文生图:任何参考图都被能力层拒绝。
      expect(
        () => caps.validate(
          prompt: 'cover',
          ratio: '1:1',
          resolution: '1K',
          references: 1,
        ),
        throwsFormatException,
      );
    });

    test('固定 Base URL 已带版本段', () {
      expect(
        aiProviderFixedBaseUrl(AiProviderType.moss),
        'https://api.mosi.cn/v1',
      );
    });
  });

  group('请求级扩展参数', () {
    test('LoRA 校验:数量上限与权重总和', () {
      const single = ImageRequestExtras(
        loras: [ModelScopeLora(repoId: 'bozoyan/Q-FEIFEI', weight: 1)],
      );
      expect(single.validateLoras(), isNull);
      expect(single.modelScopeLoras, 'bozoyan/Q-FEIFEI');

      const pair = ImageRequestExtras(
        loras: [
          ModelScopeLora(repoId: 'a/b', weight: 0.6),
          ModelScopeLora(repoId: 'c/d', weight: 0.4),
        ],
      );
      expect(pair.validateLoras(), isNull);
      expect(pair.modelScopeLoras, {'a/b': 0.6, 'c/d': 0.4});

      const unbalanced = ImageRequestExtras(
        loras: [
          ModelScopeLora(repoId: 'a/b', weight: 0.5),
          ModelScopeLora(repoId: 'c/d', weight: 0.4),
        ],
      );
      expect(unbalanced.validateLoras(), 'lora_weight_sum');

      final tooMany = ImageRequestExtras(
        loras: [
          for (var i = 0; i < 7; i++) ModelScopeLora(repoId: 'a/$i', weight: 1),
        ],
      );
      expect(tooMany.validateLoras(), 'loras_exceed_max');

      const empty = ImageRequestExtras();
      expect(empty.validateLoras(), isNull);
      expect(empty.modelScopeLoras, isNull);
    });

    test('JSON 往返保持字段', () {
      const extras = ImageRequestExtras(
        loras: [
          ModelScopeLora(repoId: 'bozoyan/Q-FEIFEI', weight: 1),
        ],
        steps: 8,
        guidance: 1.0,
        seed: 42,
        negativePrompt: 'blurry',
        promptEnhance: true,
        outputWatermark: false,
      );
      final restored = ImageRequestExtras.fromJson(extras.toJson());
      expect(restored.loras.single.repoId, 'bozoyan/Q-FEIFEI');
      expect(restored.loras.single.weight, 1);
      expect(restored.steps, 8);
      expect(restored.guidance, 1.0);
      expect(restored.seed, 42);
      expect(restored.negativePrompt, 'blurry');
      expect(restored.promptEnhance, true);
      expect(restored.outputWatermark, false);
      expect(restored.isEmpty, isFalse);
      expect(const ImageRequestExtras().isEmpty, isTrue);
    });

    test('生产请求冻结 JSON 兼容旧数据', () {
      final request = ProductionImageRequest(
        providerId: 'ms',
        modelId: 'Qwen/Qwen-Image-2.1-Turbo',
        originalPrompt: 'a',
        prompt: 'a',
        ratio: '1:1',
        resolution: '2K',
        size: '2048x2048',
        extras: const ImageRequestExtras(steps: 8),
      );
      final restored = ProductionImageRequest.fromJson(request.toJson());
      expect(restored.extras?.steps, 8);

      // 旧版本数据没有 extras 字段,读取后为 null。
      final legacy = Map<String, dynamic>.from(request.toJson())
        ..remove('extras');
      expect(ProductionImageRequest.fromJson(legacy).extras, isNull);
    });

    test('MOSS 尺寸收敛:超限等比缩小,合规原样返回', () {
      // 合规尺寸原样返回。
      expect(clampMossSize('1024x1024'), '1024x1024');
      expect(clampMossSize('2016x864'), '2016x864');

      void assertLegal(String size, {required String reason}) {
        final parts = size.split('x').map(int.parse).toList();
        expect(parts, hasLength(2), reason: reason);
        final width = parts[0];
        final height = parts[1];
        expect(width % 16, 0, reason: reason);
        expect(height % 16, 0, reason: reason);
        expect(width, greaterThanOrEqualTo(256), reason: reason);
        expect(height, greaterThanOrEqualTo(256), reason: reason);
        expect(width, lessThanOrEqualTo(2048), reason: reason);
        expect(height, lessThanOrEqualTo(2048), reason: reason);
        expect(width * height, lessThanOrEqualTo(2097152), reason: reason);
      }

      // 封面 3:4 + 2K = 1536x2048(总像素超限)收敛到合规值。
      final clamped = clampMossSize('1536x2048')!;
      expect(clamped, isNot('1536x2048'));
      assertLegal(clamped, reason: 'clamp 1536x2048 → $clamped');

      // 方形 2K 超限收敛到上限内的方形。
      final square = clampMossSize('2048x2048')!;
      assertLegal(square, reason: 'clamp 2048x2048 → $square');
      final sides = square.split('x').map(int.parse).toList();
      expect(sides[0], sides[1], reason: square);

      // 非 16 倍数的旧尺寸也被收敛对齐。
      final odd = clampMossSize('2048x1154')!;
      assertLegal(odd, reason: 'clamp 2048x1154 → $odd');

      // 非 WxH 格式原样透传。
      expect(clampMossSize('1024X768'), '1024X768');
      expect(clampMossSize(null), isNull);
    });
  });
}
