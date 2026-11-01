// 职责: 大纲节拍卡片通用 chip（序号 / 状态 / 章数）与序号配色，供架构视图与全局对比板复用。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_architecture_view.dart
//   lib/desktop/widgets/workspace/outline_global_view.dart
//   lib/desktop/widgets/workspace/outline_beat_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import 'outline_beat_dialog.dart';

/// 节拍序号 chip（「节拍 N」），颜色由调用方给定。
class OutlineBeatSequenceChip extends StatelessWidget {
  const OutlineBeatSequenceChip({
    super.key,
    required this.index,
    required this.color,
  });

  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        context.t(
          LocaleKeys.workspaceOutlineBeatSequenceLabel,
          namedArgs: {'index': '$index'},
        ),
        style: typo.uiTinySemibold.copyWith(color: color),
      ),
    );
  }
}

/// 节拍状态 chip（待开始 / 进行中 / 已完成），颜色取自 [statusColor]。
class OutlineBeatStatusChip extends StatelessWidget {
  const OutlineBeatStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final color = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        statusLabel(context, status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: typo.uiTinySemibold.copyWith(color: color),
      ),
    );
  }
}

/// 章数 chip（「N 章」）。
class OutlineBeatChapterChip extends StatelessWidget {
  const OutlineBeatChapterChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        context.t(
          LocaleKeys.workspaceOutlineBeatChapterCountValue,
          namedArgs: {'count': '$count'},
        ),
        style: typo.uiTiny.copyWith(color: colors.textMuted),
      ),
    );
  }
}

/// 节拍序号配色：按序号在强调色板中循环取色。
Color beatSequenceColor(BuildContext context, int index) {
  final colors = RevericTheme.colorsOf(context);
  final palette = <Color>[
    colors.accent,
    colors.accentWarm,
    colors.accentAmber,
    colors.success,
    colors.warningText,
  ];
  return palette[index % palette.length];
}
