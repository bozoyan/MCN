// 职责: 根据新建剧本的分类与标签选择一次初始制作风格。
// 关联文件:
//   lib/shared/models/production/style.dart
//   lib/shared/models/production/style_presets.dart
//   lib/shared/services/novel_actions.dart
//   lib/shared/services/initialization/demo_screenplay.dart
import 'style.dart';

const _fallbackId = 'premium-costume-drama';

// 同一层中按规则顺序取首个命中，标签排列不影响结果。
const _visualRules = [
  (id: 'eastern-ink-decorative', words: ['水墨', '水墨画', '国风水墨', 'ink']),
  (id: 'pixel-art', words: ['像素', '像素风', 'pixel', 'pixel art']),
  (id: 'semi-real-cg', words: ['3d', '3d动画', 'cg']),
  (id: 'guoman-anime', words: ['2d', '二次元', '动漫']),
  (id: 'cn-urban-realism', words: ['真人', '写实', '真人写实', 'live action']),
];

const _genreRules = [
  (id: 'palace-intrigue-cold', words: ['宫斗', '宫廷权谋']),
  (id: 'horror-film', words: ['恐怖', '惊悚']),
  (id: 'chinese-supernatural-film', words: ['灵异', '志怪', '悬疑灵异']),
  (id: 'cn-suspense-cold', words: ['悬疑', '推理', '悬疑推理']),
  (id: 'realist-suspense-cold', words: ['末世', '末世求生', '废土']),
  (id: 'eastern-wuxia-poetic', words: ['武侠']),
  (id: 'guoman-3d-hd', words: ['仙侠', '修真', '仙侠奇缘', '玄幻', '奇幻', '玄幻言情']),
  (id: 'premium-costume-drama', words: ['古代言情', '古言', '古装爱情']),
  (id: 'jp-youth-film', words: ['校园', '青春', '浪漫青春']),
  (id: 'cn-modern-idol-drama', words: ['现代言情', '现言', '都市言情', '言情']),
  (id: 'tech-film', words: ['科幻', '科幻空间']),
  (id: 'retro-war-film', words: ['军事', '战争']),
  (id: 'period-rural-drama', words: ['乡土', '种田']),
  (id: 'cn-urban-realism', words: ['都市', '现实', '现实生活', '商战']),
  (id: 'western-surreal-game-cg', words: ['游戏', '游戏竞技']),
  (id: 'guoman-anime', words: ['轻小说']),
];

/// 明确预设名 / ID > 画风标签 > 题材标签 > 分类；无命中使用古装偶像剧。
/// 标签和分类去首尾空白并忽略大小写，以完整词匹配，避免「非科幻」误命中。
/// 多个明确预设按 ID 排序选择，其他多命中按规则顺序选择。
ProductionStylePreset initialProductionStyle({
  String? category,
  List<String> tags = const [],
}) {
  final tokens = tags.map((tag) => tag.trim().toLowerCase()).toSet();
  final named =
      builtinProductionStyles
          .where(
            (preset) =>
                tokens.contains(preset.name.toLowerCase()) ||
                tokens.contains(preset.id) ||
                tokens.contains('$productionStylePresetPrefix${preset.id}'),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (named.isNotEmpty) {
    return named.first;
  }
  for (final rule in _visualRules) {
    if (rule.words.any(tokens.contains)) {
      return productionStylePreset(rule.id)!;
    }
  }
  for (final rule in _genreRules) {
    if (rule.words.any(tokens.contains)) {
      return productionStylePreset(rule.id)!;
    }
  }
  final normalizedCategory = category?.trim().toLowerCase();
  for (final rule in _genreRules) {
    if (rule.words.contains(normalizedCategory)) {
      return productionStylePreset(rule.id)!;
    }
  }
  return productionStylePreset(_fallbackId)!;
}
