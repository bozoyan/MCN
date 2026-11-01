// 职责: 测试 PromptRegistry 的注册完整性，确保 prompt ID 和资产路径稳定可查。
// 关联文件:
//   lib/shared/services/ai/prompts/prompt_registry.dart
//   lib/shared/services/ai/prompts/prompt_definition.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/prompts/prompt_registry.dart';

void main() {
  group('PromptRegistry', () {
    test('prompt id 不重复', () {
      final ids = PromptRegistry.definitions
          .map((definition) => definition.id)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('模板路径不重复', () {
      final paths = PromptRegistry.templateAssetPaths;
      expect(paths.toSet(), hasLength(paths.length));
    });

    test('注册的模板路径都有对应 asset 文件', () {
      for (final path in PromptRegistry.templateAssetPaths) {
        expect(
          File('$path.md').existsSync(),
          isTrue,
          reason: 'Missing prompt template asset: $path.md',
        );
      }
    });

    test('所有注册项都有 owner', () {
      for (final definition in PromptRegistry.definitions) {
        expect(
          definition.owner.trim(),
          isNotEmpty,
          reason: 'Prompt owner is required: ${definition.id}',
        );
      }
    });
  });
}
