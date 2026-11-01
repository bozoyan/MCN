// 职责: 实体关系图关系概览环形图 — 分类占比甜甜圈 + 顶部分类图例。
// 关联文件:
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/constants.dart
//   lib/desktop/widgets/sidebar/entity_list_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'dart:math';

import 'package:flutter/material.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'colors.dart';
import 'constants.dart';
import 'labels.dart';

/// 关系概览环形图 — 侧栏底部展示全量关系的分类占比。
class EntityGraphOverviewDonut extends StatelessWidget {
  const EntityGraphOverviewDonut({super.key, required this.counts});

  final Map<RelationCategory, int> counts;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final total = counts.values.fold(0, (sum, n) => sum + n);
    final segments = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.entityGraphOverviewTitle),
            style: typo.uiTinySemibold.copyWith(
              color: colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Row(
            children: [
              SizedBox(
                width: kEntityGraphDonutSize,
                height: kEntityGraphDonutSize,
                child: CustomPaint(
                  painter: _DonutPainter(
                    segments: segments
                        .map(
                          (e) => (
                            color: relationCategoryColor(e.key),
                            fraction: total == 0 ? 0.0 : e.value / total,
                          ),
                        )
                        .toList(),
                    trackColor: colors.border,
                    centerLabel: '$total',
                    centerSubLabel: context.t(
                      LocaleKeys.entityGraphRelationsUnit,
                    ),
                    numStyle: typo.uiMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    subStyle: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final seg in segments.take(6))
                      _OverviewRow(
                        label: localizeRelationCategoryLabel(context, seg.key),
                        color: relationCategoryColor(seg.key),
                        count: seg.value,
                        percent: total == 0 ? 0 : seg.value / total,
                        colors: colors,
                        typo: typo,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.label,
    required this.color,
    required this.count,
    required this.percent,
    required this.colors,
    required this.typo,
  });

  final String label;
  final Color color;
  final int count;
  final double percent;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiTiny.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            '${(percent * 100).round()}%',
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
          const SizedBox(width: RevericSpacing.xs),
          SizedBox(
            width: 16,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: typo.uiTiny.copyWith(color: colors.textSubtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.trackColor,
    required this.centerLabel,
    required this.centerSubLabel,
    required this.numStyle,
    required this.subStyle,
  });

  final List<({Color color, double fraction})> segments;
  final Color trackColor;
  final String centerLabel;
  final String centerSubLabel;
  final TextStyle numStyle;
  final TextStyle subStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(
      center: center,
      radius: kEntityGraphDonutRadius,
    );

    if (segments.isEmpty || segments.every((s) => s.fraction == 0)) {
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi,
        false,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = kEntityGraphDonutStrokeWidth,
      );
    } else {
      var start = -pi / 2;
      for (final seg in segments) {
        final sweep = 2 * pi * seg.fraction;
        if (sweep > 0) {
          canvas.drawArc(
            rect,
            start,
            sweep,
            false,
            Paint()
              ..color = seg.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = kEntityGraphDonutStrokeWidth
              ..strokeCap = StrokeCap.butt,
          );
          start += sweep;
        }
      }
    }

    final numPainter = TextPainter(
      text: TextSpan(text: centerLabel, style: numStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    numPainter.paint(
      canvas,
      Offset(
        center.dx - numPainter.width / 2,
        center.dy - numPainter.height - 1,
      ),
    );

    final subPainter = TextPainter(
      text: TextSpan(text: centerSubLabel, style: subStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    subPainter.paint(
      canvas,
      Offset(center.dx - subPainter.width / 2, center.dy + 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.centerLabel != centerLabel ||
        oldDelegate.centerSubLabel != centerSubLabel;
  }
}
