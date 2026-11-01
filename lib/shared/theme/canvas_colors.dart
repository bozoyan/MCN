// 职责: 画布专用色 — 边色/线型、便签纸色、refType 强调色、卡片阴影、点网格，全部从语义 token 派生；
//       画布与导出预览 SVG 共用。
// 关联文件:
//   lib/shared/theme/reveric_colors.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/services/canvas_export/svg.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../database/novel_content_database.dart';
import '../models/canvas_layout.dart';
import 'reveric_colors.dart';

/// 画布专用色的唯一来源。
///
/// 画布需要一批 [RevericColors] 没有的语义色(5 类边、4 种便签纸色、按资源
/// 类型分色的节点强调色)。这些色**不进** [RevericColors]——那有 24 套预设,
/// 加一个字段要改 24 处。改为在此从既有语义 token 派生:主题换肤时自动适配,
/// widget 内也就不需要任何颜色字面量(见 design-system.md 的硬编码禁令)。
///
/// 设计参考 `designs/desktop/canvas/canvas.css` 的 `--cv-*` token。

// ---- 边:颜色 / 线型 / 方向 ----

/// 边线相对画布底的最低对比度。
///
/// 连线是 ~2px 的图形元素,WCAG 对非文本图形要求 3:1。部分主题的 accent /
/// warning token 本就偏浅(如 verdant 的 accent 落在画布底上只有 1.63),
/// 直接拿来画线会几乎看不见——所以派生后必须过一道下限。
const double _minEdgeContrast = 3.0;

/// 按边类型取线色。5 类边必须一眼可分,故各自绑定不同语义 token。
///
/// 派生出的色再按 [_minEdgeContrast] 压暗/提亮,保证在任何主题的画布底上都看得清。
Color canvasEdgeColor(RevericColors colors, String type) {
  final base = switch (type) {
    canvasEdgeTypeRelationship => colors.accentWarm,
    canvasEdgeTypeCausal => colors.accent,
    canvasEdgeTypeTimeline => colors.success,
    // 伏笔兑现用警示色,与 mockup 的 #D97706 同源(warningText)。
    canvasEdgeTypeForeshadowPayoff => colors.warningText,
    canvasEdgeTypeAssociation => colors.textMuted,
    _ => colors.textMuted,
  };
  return _ensureContrast(base, colors.canvas, _minEdgeContrast);
}

/// WCAG 相对对比度。
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final high = la > lb ? la : lb;
  final low = la > lb ? lb : la;
  return (high + 0.05) / (low + 0.05);
}

/// 把 [color] 朝远离 [background] 的方向推,直到对比度达到 [minRatio]。
///
/// 只调明度不换色相:边类型之间靠色相区分,压暗/提亮不应让两类边撞色。
Color _ensureContrast(Color color, Color background, double minRatio) {
  if (_contrastRatio(color, background) >= minRatio) {
    return color;
  }
  // 底色浅就压暗,底色深就提亮。
  final target = background.computeLuminance() > 0.5
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  var result = color;
  for (var step = 1; step <= 12; step++) {
    result = Color.lerp(color, target, step / 12) ?? color;
    if (_contrastRatio(result, background) >= minRatio) {
      return result;
    }
  }
  return result;
}

/// 按边类型取虚线样式;null 表示实线。
///
/// 「伏笔兑现」用长虚线、「通用关联」用点线——这两类语义偏弱,线型上也弱化,
/// 与 mockup 的 `dash: "7 6"` / `"2 6"` 对应。
List<double>? canvasEdgeDashPattern(String type) {
  return switch (type) {
    canvasEdgeTypeForeshadowPayoff => const [7, 6],
    canvasEdgeTypeAssociation => const [2, 6],
    _ => null,
  };
}

/// 该类型的边是否画箭头。
///
/// 「人物关系」与「通用关联」在语义上无向(底层仍是有向存储,只是不画箭头),
/// 其余三类表达先后/因果/兑现,方向是信息本身。
bool canvasEdgeDirected(String type) => isCanvasEdgeDirected(type);

// ---- 节点颜色 ----

/// 鲜艳色的固定色相。不从主题派生：用户挑「红」就该是红，换主题也不变。
const Map<String, Color> _canvasVividHues = {
  canvasNodeColorRed: Color(0xFFEF4444),
  canvasNodeColorOrange: Color(0xFFF97316),
  canvasNodeColorYellow: Color(0xFFEAB308),
  canvasNodeColorGreen: Color(0xFF22C55E),
  canvasNodeColorTeal: Color(0xFF14B8A6),
  canvasNodeColorBlue: Color(0xFF3B82F6),
  canvasNodeColorPurple: Color(0xFFA855F7),
  canvasNodeColorPink: Color(0xFFEC4899),
};

/// 颜色值对应的色相(色块、边框、选中环用)；非法值返回 null。
Color? canvasNodeHueColor(RevericColors colors, String? value) {
  if (value == null) {
    return null;
  }
  final soft = switch (value) {
    canvasStickyColorSage => colors.success,
    canvasStickyColorRose => colors.error,
    canvasStickyColorStone => colors.textMuted,
    canvasStickyColorSand => colors.accentWarm,
    _ => null,
  };
  if (soft != null) {
    return soft;
  }
  final vivid = _canvasVividHues[value];
  if (vivid != null) {
    return vivid;
  }
  if (!isCanvasNodeColorValue(value)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

/// 把色相序列化为自定义颜色值 `#RRGGBB`。
String canvasNodeCustomColorValue(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 按颜色值取卡片底色。
///
/// 底色是「一张纸」而非「一块色卡」:用低透明度色相叠在 surface 上,亮暗主题
/// 下都保持纸感且正文可读。鲜艳色/自定义色叠得更重一些，否则和纸色拉不开。
Color canvasNodePaperColor(RevericColors colors, String value) {
  final hue =
      canvasNodeHueColor(colors, value) ??
      canvasNodeHueColor(colors, canvasStickyColorDefault)!;
  final soft = canvasStickyColorKeys.contains(value);
  final alpha = soft
      ? (colors.isDark ? 0.16 : 0.13)
      : (colors.isDark ? 0.24 : 0.18);
  return Color.alphaBlend(hue.withValues(alpha: alpha), colors.surface);
}

/// 按纸色 key 取便签底色；缺省用默认纸色。
Color canvasStickyPaperColor(RevericColors colors, String? key) =>
    canvasNodePaperColor(colors, key ?? canvasStickyColorDefault);

/// 便签墨色(标题/正文/署名共用一个色相,靠透明度分层)。
Color canvasStickyInkColor(RevericColors colors) => colors.textPrimary;

/// 从便签 style 读颜色值;缺失或非法时回落默认色。
///
/// style 是可选的纯视觉列,老数据没有该字段属正常状态,不是错误。
String canvasStickyColorKeyOf(Map<String, dynamic>? style) =>
    canvasNodeColorValueOf(style) ?? canvasStickyColorDefault;

// ---- 引用节点:按资源类型分色 ----

/// 按 refType 取强调色(节点图标底、选中描边)。
///
/// 同一类资源在画布上应保持同一个色相,作者扫一眼就能分出人物/章节/伏笔。
Color canvasRefTypeAccent(RevericColors colors, String refType) {
  return switch (refType) {
    entityTypeCharacter => colors.accentWarm,
    entityTypeChapter => colors.accent,
    entityTypeForeshadowing => colors.warningText,
    canvasNodeRefTypeOutline => colors.textMuted,
    entityTypeLocation => colors.success,
    entityTypeItem => colors.accent,
    entityTypeFaction => colors.textSecondary,
    entityTypeSkill => colors.accentAmber,
    entityTypeCreature => colors.success,
    canvasNodeRefTypeDocument => colors.textMuted,
    _ => colors.accent,
  };
}

// ---- 节点卡片:阴影与选中环 ----

/// 节点卡片投影(对齐 `--cv-shadow-node` 的双层阴影)。
///
/// 单层大 blur 会让卡片显得"浮"；设计稿用「1px 贴地 + 12px 扩散」两层，
/// 近处交代边缘、远处交代层级，纸感更稳。
List<BoxShadow> canvasNodeShadows(RevericColors colors) {
  final ink = Colors.black.withValues(alpha: colors.isDark ? 0.30 : 0.06);
  final spread = Colors.black.withValues(alpha: colors.isDark ? 0.28 : 0.06);
  return [
    BoxShadow(color: ink, blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(color: spread, blurRadius: 12, offset: const Offset(0, 4)),
  ];
}

/// 选中态的 3px 强调色外环(对齐 `0 0 0 3px color-mix(accent 26%)`)。
///
/// Flutter 没有 CSS 的 spread-only 阴影，用 blurRadius 0 + spreadRadius 3 等价实现。
BoxShadow canvasNodeSelectionRing(RevericColors colors, Color accent) {
  return BoxShadow(
    color: accent.withValues(alpha: colors.isDark ? 0.34 : 0.26),
    blurRadius: 0,
    spreadRadius: 3,
  );
}

// ---- 画布浮层:半透明表面 ----
//
// 画布是 DESIGN.md 里「flat by default」的例外区:节点卡和悬浮控件是浮在点阵上
// 的半透明层,靠「半透明底 + 发丝描边 + 大圆角」分层。深浅两套取法不同:
// 深色画布上投影看不见,层次靠比画布略亮的底色;浅色画布上底色与画布接近,
// 层次靠描边和一层很淡的投影。

/// 浮层底色。[raised] 用于悬停态和承载输入的浮层(输入框、工具条),更实一些。
Color canvasGlassFill(RevericColors colors, {bool raised = false}) {
  if (colors.isDark) {
    return Color.lerp(
      colors.canvas,
      colors.textPrimary,
      raised ? 0.13 : 0.10,
    )!.withValues(alpha: raised ? 0.88 : 0.76);
  }
  return colors.surface.withValues(alpha: raised ? 0.94 : 0.84);
}

/// 浮层发丝描边;[strong] 用于悬停。
Color canvasGlassBorder(RevericColors colors, {bool strong = false}) {
  final alpha = colors.isDark ? (strong ? 0.20 : 0.08) : (strong ? 0.22 : 0.10);
  return colors.textPrimary.withValues(alpha: alpha);
}

/// 浮层里按钮、菜单行的悬停底:一层极淡的墨色,不抢浮层本身的底色。
Color canvasGlassHover(RevericColors colors) {
  return colors.textPrimary.withValues(alpha: colors.isDark ? 0.06 : 0.05);
}

/// 卡片里的画面槽(空画面、待生成),比外层再沉一级。
Color canvasNodeWell(RevericColors colors) {
  return colors.isDark
      ? colors.canvas.withValues(alpha: 0.45)
      : colors.textPrimary.withValues(alpha: 0.04);
}

/// 悬浮控件投影:大而淡,只交代「浮在画布上」。
List<BoxShadow> canvasGlassShadows(RevericColors colors) {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: colors.isDark ? 0.32 : 0.08),
      blurRadius: 32,
      offset: const Offset(0, 10),
    ),
  ];
}

/// 节点卡投影:浅色画布上靠它浮起;深色画布上看不见,不画。
List<BoxShadow> canvasGlassNodeShadows(
  RevericColors colors, {
  bool hovered = false,
}) {
  if (colors.isDark) {
    return const [];
  }
  return [
    BoxShadow(
      color: colors.textPrimary.withValues(alpha: hovered ? 0.10 : 0.05),
      blurRadius: hovered ? 22 : 14,
      offset: Offset(0, hovered ? 8 : 4),
    ),
  ];
}

/// 制作画布的连线:低对比细线,不和画面抢视线。
Color canvasSoftEdgeColor(RevericColors colors) {
  return colors.textPrimary.withValues(alpha: colors.isDark ? 0.20 : 0.24);
}

// ---- 画布底 ----

/// 画布点网格颜色。只做空间参照,压低对比让节点靠自身描边浮出。
Color canvasGridDotColor(RevericColors colors) {
  return colors.textMuted.withValues(alpha: colors.isDark ? 0.16 : 0.20);
}

/// 制作画布的细密点阵:点更小更密,读作底纹而不是网格。
Color canvasFineDotColor(RevericColors colors) {
  return colors.textMuted.withValues(alpha: colors.isDark ? 0.30 : 0.34);
}

// ---- flow 主题 ----
