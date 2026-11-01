// 职责: 画布调色板测试 — 边色在所有主题下可辨且达对比度下限、便签正文可读、纸色 key 解析
// 关联文件:
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/theme/reveric_colors.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_palette.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/theme/theme.dart';

/// 项目全部主题预设(明/暗各一)。画布用色是从语义 token 派生的,
/// 任何一套主题的 accent 偏浅都会让连线在画布上看不见,故逐套校验。
const Map<String, RevericColors> _allThemes = {
  'classic': RevericColors.classic,
  'classicDark': RevericColors.classicDark,
  'ivory': RevericColors.ivory,
  'ivoryDark': RevericColors.ivoryDark,
  'reveric': RevericColors.reveric,
  'revericDark': RevericColors.revericDark,
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final high = la > lb ? la : lb;
  final low = la > lb ? lb : la;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  group('canvasEdgeColor', () {
    test('every edge type stays visible on the board in all themes', () {
      // 连线是 ~2px 图形元素,WCAG 对非文本图形要求 3:1。
      // 不设下限时 verdant 的 causal 只有 1.63,画在画布上几乎看不见。
      _allThemes.forEach((name, colors) {
        for (final type in canvasEdgeTypes) {
          final ratio = _contrast(canvasEdgeColor(colors, type), colors.canvas);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '$name / $type 对画布底只有 ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });

    test('the five edge types remain mutually distinguishable', () {
      // 提升对比度时只调明度不换色相,压暗后仍不能撞色——否则「因果」与
      // 「人物关系」会变成同一条线。
      _allThemes.forEach((name, colors) {
        final distinct = {
          for (final type in canvasEdgeTypes)
            canvasEdgeColor(colors, type).toARGB32(),
        };
        expect(
          distinct,
          hasLength(canvasEdgeTypes.length),
          reason: '$name 下有边类型撞色',
        );
      });
    });
  });

  group('canvasStickyPaperColor', () {
    test('sticky body text stays readable on every paper tint', () {
      _allThemes.forEach((name, colors) {
        for (final key in canvasNodeColorKeys) {
          final paper = canvasStickyPaperColor(colors, key);
          // 正文用 88% 墨色(与 CanvasStickyNodeCard 一致)。
          final ink = canvasStickyInkColor(colors).withValues(alpha: 0.88);
          final ratio = _contrast(Color.alphaBlend(ink, paper), paper);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name / $key 正文对比只有 ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });

    test('the four paper tints are distinguishable from each other', () {
      _allThemes.forEach((name, colors) {
        final distinct = {
          for (final key in canvasStickyColorKeys)
            canvasStickyPaperColor(colors, key).toARGB32(),
        };
        expect(
          distinct,
          hasLength(canvasStickyColorKeys.length),
          reason: '$name 下有纸色撞色',
        );
      });
    });
  });

  group('canvasStickyColorKeyOf', () {
    test('falls back to the default tint for missing or unknown style', () {
      // style 是可选的纯视觉列,老数据没有该字段属正常状态,不是错误。
      expect(canvasStickyColorKeyOf(null), canvasStickyColorDefault);
      expect(canvasStickyColorKeyOf(const {}), canvasStickyColorDefault);
      expect(
        canvasStickyColorKeyOf(const {canvasNodeColorStyleKey: 'chartreuse'}),
        canvasStickyColorDefault,
      );
      expect(
        canvasStickyColorKeyOf(const {canvasNodeColorStyleKey: 123}),
        canvasStickyColorDefault,
      );
    });

    test('reads current vivid keys and custom hex', () {
      expect(
        canvasStickyColorKeyOf(const {canvasNodeColorStyleKey: 'blue'}),
        'blue',
      );
      expect(
        canvasNodeColorValueOf(const {canvasNodeColorStyleKey: '#12ab9F'}),
        '#12ab9F',
      );
      expect(
        canvasNodeColorValueOf(const {canvasNodeColorStyleKey: '#12ab9'}),
        isNull,
      );
      // 新字段优先于旧字段。
      expect(
        canvasNodeColorValueOf(const {
          canvasNodeColorStyleKey: 'red',
          'sticky_color': 'sage',
        }),
        'red',
      );
      expect(canvasNodeColorValueOf(null), isNull);
    });

    test('custom hex round-trips through the hue color', () {
      final colors = _allThemes.values.first;
      final hue = canvasNodeHueColor(colors, '#12AB9F')!;
      expect(canvasNodeCustomColorValue(hue), '#12AB9F');
    });

    test('writing a color replaces the current field and keeps other keys', () {
      expect(
        canvasStyleWithColor(const {
          canvasNodeColorStyleKey: 'sage',
          'other': 1,
        }, 'pink'),
        {'other': 1, canvasNodeColorStyleKey: 'pink'},
      );
      expect(
        canvasStyleWithColor(const {canvasNodeColorStyleKey: 'pink'}, null),
        isEmpty,
      );
    });

    test('reads a known tint key back', () {
      expect(
        canvasStickyColorKeyOf(const {
          canvasNodeColorStyleKey: canvasStickyColorSage,
        }),
        canvasStickyColorSage,
      );
    });
  });
}
