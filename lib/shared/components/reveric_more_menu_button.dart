// 职责: Reveric 通用「…」更多操作按钮 — 点击在按钮下方弹出 Reveric 上下文菜单
// 关联文件:
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'reveric_context_menu.dart';

/// 卡片/面板右上角的「…」按钮，删除等低频或危险操作收在这里。
///
/// [entries] 在点击时才构建，菜单项可以读取点击那一刻的最新状态。
class RevericMoreMenuButton extends StatelessWidget {
  const RevericMoreMenuButton({
    super.key,
    required this.entries,
    this.iconSize = 18,
  });

  final List<RevericMenuEntry> Function() entries;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: context.t(LocaleKeys.commonMoreActions),
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () {
          final renderBox = context.findRenderObject()! as RenderBox;
          final origin = renderBox.localToGlobal(Offset.zero);
          unawaited(
            showRevericContextMenu(
              context: context,
              position: Offset(
                origin.dx,
                origin.dy + renderBox.size.height + RevericSpacing.xs,
              ),
              entries: entries(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(RevericRadius.small),
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.xs),
          child: RevericIcon(
            RevericIcons.more_horiz,
            size: iconSize,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}
