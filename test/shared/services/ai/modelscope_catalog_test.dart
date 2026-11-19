// 职责: 验证魔搭 LoRA 外置清单的解析、去重、触发词反查与前置拼接。
// 关联文件:
//   lib/shared/services/ai/modelscope_catalog.dart
//   lib/shared/models/image/extras.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/image/extras.dart';
import 'package:reveric/shared/services/ai/modelscope_catalog.dart';

ModelScopeCatalogEntry _entry({
  required String model,
  required String trigger,
  String category = 'LORA',
}) => ModelScopeCatalogEntry(
  category: category,
  modelId: model,
  baseModel: 'Qwen-Image-2.1-Turbo',
  triggerWord: trigger,
);

void main() {
  group('ModelScopeLoraCatalog 解析', () {
    test('遍历所有分类数组并按 Model 去重', () {
      final catalog = ModelScopeLoraCatalog.fromJson({
        'LORA': [
          {
            'Name': 'YANBO',
            'Model': 'bozoyan/YANBO',
            'Bmodel': 'Qwen-Image-2.1-Turbo',
            'prompt': 'q-yanbo',
          },
          {
            'Name': '重复',
            'Model': 'bozoyan/YANBO',
            'Bmodel': 'Qwen-Image-2.1-Turbo',
            'prompt': 'another',
          },
        ],
        'EDIT': [
          {
            'Name': '高清',
            'Model': 'bozoyan/high_quality',
            'Bmodel': 'Qwen-Image-2.1-Turbo',
            'prompt': 'high quality',
          },
        ],
        '不是数组': 'ignore-me',
      });

      expect(catalog.entries, hasLength(2));
      expect(catalog.entries.map((e) => e.category), ['LORA', 'EDIT']);
      expect(catalog.triggerFor('bozoyan/YANBO'), 'q-yanbo');
      expect(catalog.triggerFor('bozoyan/high_quality'), 'high quality');
      expect(catalog.triggerFor('不存在的模型'), isNull);
    });

    test('空触发词不进反查表', () {
      final catalog = ModelScopeLoraCatalog.fromJson({
        'FEI': [
          {'Model': 'bozoyan/FEI', 'Bmodel': 'FLUX.1-dev', 'prompt': ''},
        ],
      });
      expect(catalog.entries, hasLength(1));
      expect(catalog.triggerFor('bozoyan/FEI'), isNull);
    });
  });

  group('ModelScopeLoraCatalog 触发词前置', () {
    final catalog = ModelScopeLoraCatalog.forTesting([
      _entry(model: 'bozoyan/Q-YANBO', trigger: 'q-yanbo'),
      _entry(model: 'bozoyan/Q-WEIQIN', trigger: 'q-weiqin'),
      _entry(model: 'bozoyan/FEI', trigger: ''),
    ]);

    test('单 LoRA 触发词拼在最前', () {
      final result = catalog.prefixTriggers('a cat on the moon', [
        const ModelScopeLora(repoId: 'bozoyan/Q-YANBO', weight: 1),
      ]);
      expect(result, 'q-yanbo, a cat on the moon');
    });

    test('多 LoRA 触发词按序拼接并去重', () {
      final result = catalog.prefixTriggers('a cat', [
        const ModelScopeLora(repoId: 'bozoyan/Q-YANBO', weight: 0.6),
        const ModelScopeLora(repoId: 'bozoyan/Q-WEIQIN', weight: 0.4),
        const ModelScopeLora(repoId: 'bozoyan/Q-YANBO', weight: 0.4),
      ]);
      expect(result, 'q-yanbo, q-weiqin, a cat');
    });

    test('无命中或空触发词时原样返回用户提示词', () {
      expect(
        catalog.prefixTriggers('a cat', [
          const ModelScopeLora(repoId: '未登记', weight: 1),
        ]),
        'a cat',
      );
      expect(
        catalog.prefixTriggers('a cat', [
          const ModelScopeLora(repoId: 'bozoyan/FEI', weight: 1),
        ]),
        'a cat',
      );
      expect(catalog.prefixTriggers('a cat', const []), 'a cat');
    });
  });
}
