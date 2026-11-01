// 职责: 验证作品与技能表单无需后端配置即可取得本地分类和标签候选。
// 关联文件:
//   lib/shared/providers/dictionary_providers.dart
//   lib/shared/models/novel_categories.dart
//   lib/shared/models/dictionary_fallbacks.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/dictionary_fallbacks.dart';
import 'package:reveric/shared/models/novel_categories.dart';
import 'package:reveric/shared/providers/dictionary_providers.dart';

void main() {
  test('local form candidates work without backend configuration', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(novelCategoriesProvider.future),
      novelCategorySuggestions,
    );
    expect(await container.read(novelTagsProvider.future), kFallbackNovelTags);
    expect(
      await container.read(skillCategoriesProvider.future),
      kFallbackSkillCategories,
    );
    expect(await container.read(skillTagsProvider.future), kFallbackSkillTags);
  });
}
