// 职责: 编辑面板标题栏面包屑 — 统一渲染「分类 > 当前项」导航标题
// 关联文件:
//   lib/shared/theme/theme.dart
//   lib/desktop/widgets/agent_management/subagent_edit_panel.dart
//   lib/desktop/widgets/agent_management/ai_shortcut_action_edit_panel.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../shared/theme/theme.dart';

class EditPanelBreadcrumb extends StatelessWidget {
  const EditPanelBreadcrumb({
    super.key,
    required this.rootLabel,
    required this.title,
  });

  final String rootLabel;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BreadcrumbText(label: rootLabel),
        _BreadcrumbSeparator(),
        Flexible(child: _BreadcrumbText(label: title, active: true)),
      ],
    );
  }
}

class _BreadcrumbText extends StatelessWidget {
  const _BreadcrumbText({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      label,
      style: (active ? typo.uiMedium : typo.ui).copyWith(
        color: active ? colors.textPrimary : colors.textMuted,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _BreadcrumbSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.xs),
      child: Text('>', style: typo.ui.copyWith(color: colors.textSubtle)),
    );
  }
}
