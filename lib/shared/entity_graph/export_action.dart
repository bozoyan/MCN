// 职责: 关系图 PNG 导出的 widget 层胶水 — 从主题与 i18n 组装样式、水印与图例后触发导出。
// 关联文件:
//   lib/shared/entity_graph/png_export.dart
//   lib/shared/entity_graph/legend.dart
//   lib/shared/entity_graph/labels.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'colors.dart';
import 'data.dart';
import 'labels.dart';
import 'legend.dart';
import 'models.dart';
import 'png_export.dart';

/// 从当前主题解析导出配色与文字样式。
EntityGraphPngStyle entityGraphPngStyleOf(BuildContext context) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  // ui* 排版 token 不带 fontFamily（由 ThemeData 注入），直接交给 TextPainter 会退化成系统默认字体。
  final fontFamily = DefaultTextStyle.of(context).style.fontFamily;
  return EntityGraphPngStyle(
    background: colors.canvas,
    dotColor: colors.border,
    legendBackground: colors.surfaceContainer,
    legendBorder: colors.borderSubtle,
    titleStyle: typo.uiSmallSemibold.copyWith(
      color: colors.textMuted,
      fontFamily: fontFamily,
    ),
    legendTitleStyle: typo.uiTinySemibold.copyWith(
      color: colors.textMuted,
      fontFamily: fontFamily,
    ),
    legendItemStyle: typo.uiTiny.copyWith(
      color: colors.textSecondary,
      fontFamily: fontFamily,
    ),
  );
}

/// 导出水印文案：`《小说名》· 关系图谱 · yyyy-MM-dd HH:mm`。
String entityGraphExportTitle(
  BuildContext context, {
  String? novelTitle,
  required DateTime now,
}) {
  final graphLabel = context.t(LocaleKeys.entityGraphTitle);
  final name = (novelTitle ?? '').trim();
  final stamp = DateFormat('yyyy-MM-dd HH:mm').format(now);
  return name.isEmpty
      ? '$graphLabel · $stamp'
      : '《$name》· $graphLabel · $stamp';
}

/// 图例条目（分类色 + 已本地化文案），顺序与画布底部图例一致。
List<EntityGraphPngLegendEntry> entityGraphExportLegend(
  BuildContext context,
  List<EntityEdgeData> edges,
) {
  final counts = relationCategoryCounts(edges);
  return [
    for (final category in entityGraphLegendCategories(counts))
      EntityGraphPngLegendEntry(
        label: localizeRelationCategoryLabel(context, category),
        color: relationCategoryColor(category),
      ),
  ];
}

/// 导出当前关系图为 PNG：桌面写入用户选择的路径，移动端走系统分享面板。
/// 异常向上抛出，由调用方记日志并做本地化提示。
Future<EntityGraphPngSaveResult> runEntityGraphPngExport(
  BuildContext context, {
  required EntityGraphExportController controller,
  required List<EntityEdgeData> edges,
  String? novelTitle,
}) {
  final graphLabel = context.t(LocaleKeys.entityGraphTitle);
  final name = (novelTitle ?? '').trim();
  final now = DateTime.now();
  final fileName =
      '${[if (name.isNotEmpty) name, graphLabel, DateFormat('yyyyMMdd-HHmm').format(now)].join('-')}.png';

  return exportEntityGraphPng(
    controller: controller,
    style: entityGraphPngStyleOf(context),
    titleText: entityGraphExportTitle(
      context,
      novelTitle: novelTitle,
      now: now,
    ),
    legendTitle: context.t(LocaleKeys.entityGraphLegendTitle),
    legend: entityGraphExportLegend(context, edges),
    fileName: fileName,
  );
}
