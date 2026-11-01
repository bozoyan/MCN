// 职责: 验证新剧本风格选择的优先级、稳定性、题材映射与未命中兜底。
// 关联文件:
//   lib/shared/models/production/default_style.dart
//   lib/shared/models/production/style.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/production/default_style.dart';
import 'package:reveric/shared/models/production/style.dart';

void main() {
  test('empty, unknown and ambiguous metadata use costume romance', () {
    expect(initialProductionStyle().id, 'premium-costume-drama');
    expect(initialProductionStyle().name, '古装偶像剧');
    for (final value in [' ', '未知分类', '重生', '穿越', '短篇', '非科幻']) {
      expect(
        initialProductionStyle(category: value, tags: [value]).id,
        'premium-costume-drama',
        reason: value,
      );
    }
  });

  test(
    'explicit preset IDs and names take priority over genre and visual tags',
    () {
      for (final preset in builtinProductionStyles) {
        expect(
          initialProductionStyle(category: '都市', tags: [preset.id, '3D']).id,
          preset.id,
        );
      }
      expect(
        initialProductionStyle(category: '武侠', tags: [' 水墨 ', ' 像素动画 ']).id,
        'pixel-art',
      );
      expect(
        initialProductionStyle(tags: [' PRESET:PIXEL-ART ']).id,
        'pixel-art',
      );
    },
  );

  test(
    'visual tags override genre tags and category; normalize case and whitespace',
    () {
      for (final entry in {
        ' 水墨 ': 'eastern-ink-decorative',
        ' PIXEL ART ': 'pixel-art',
        ' 3D ': 'semi-real-cg',
        ' 2D ': 'guoman-anime',
        '真人': 'cn-urban-realism',
      }.entries) {
        expect(
          initialProductionStyle(category: '武侠', tags: ['悬疑', entry.key]).id,
          entry.value,
        );
      }
    },
  );

  test('genre tags override category and conflicting tag order is stable', () {
    expect(
      initialProductionStyle(category: '都市', tags: ['武侠']).id,
      'eastern-wuxia-poetic',
    );
    for (final tags in [
      ['都市', '校园', '宫斗'],
      ['宫斗', '校园', '都市', '宫斗'],
    ]) {
      expect(initialProductionStyle(tags: tags).id, 'palace-intrigue-cold');
    }
    expect(
      initialProductionStyle(tags: ['3D', '水墨']).id,
      initialProductionStyle(tags: ['水墨', '3D']).id,
    );
    expect(
      initialProductionStyle(
        tags: ['pixel-art', 'chinese-supernatural-film'],
      ).id,
      initialProductionStyle(
        tags: ['chinese-supernatural-film', 'pixel-art'],
      ).id,
    );
  });

  test('common categories map to existing presets', () {
    for (final entry in {
      '宫斗': 'palace-intrigue-cold',
      '恐怖': 'horror-film',
      '悬疑灵异': 'chinese-supernatural-film',
      '悬疑推理': 'cn-suspense-cold',
      '末世': 'realist-suspense-cold',
      ' 武侠 ': 'eastern-wuxia-poetic',
      '仙侠奇缘': 'guoman-3d-hd',
      '玄幻言情': 'guoman-3d-hd',
      '古代言情': 'premium-costume-drama',
      '浪漫青春': 'jp-youth-film',
      '现代言情': 'cn-modern-idol-drama',
      '科幻空间': 'tech-film',
      '军事': 'retro-war-film',
      '种田': 'period-rural-drama',
      '现实生活': 'cn-urban-realism',
      '游戏竞技': 'western-surreal-game-cg',
      '轻小说': 'guoman-anime',
    }.entries) {
      expect(initialProductionStyle(category: entry.key).id, entry.value);
    }
  });
}
