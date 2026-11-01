// 职责: 可折叠的列表分组 — 标题行展示名称与计数，点击折叠/展开组内条目。
// 关联文件:
//   lib/shared/entity_graph/entity_list_section.dart
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 分组标题行 — 展示图标、名称、计数与折叠箭头。
///
/// 需要惰性构建（`ListView.builder` 把分组和条目拍平成行）时直接用它，
/// 由调用方持有展开状态；条目数量可控时用 [CollapsibleListGroup] 更省事。
class CollapsibleListGroupHeader extends StatelessWidget {
  const CollapsibleListGroupHeader({
    super.key,
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
    this.leading,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.x2l,
          vertical: RevericSpacing.sm,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: RevericSpacing.sm),
            ],
            Expanded(
              child: Text(
                title,
                style: typo.uiSmallSemibold.copyWith(
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: RevericSpacing.xxs),
            Text(
              '$count',
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            const SizedBox(width: RevericSpacing.xs),
            RevericIcon(
              expanded
                  ? RevericIcons.expand_less_rounded
                  : RevericIcons.expand_more,
              size: 14,
              color: colors.textSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧栏列表内的分组容器。默认展开，折叠态只保留标题行。
/// 一次性构建全部 [children]，仅适用于条目数量可控的分组。
class CollapsibleListGroup extends StatefulWidget {
  const CollapsibleListGroup({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.leading,
    this.initiallyExpanded = true,
  });

  final String title;
  final int count;
  final List<Widget> children;

  /// 标题左侧的可选图标，用于区分组类型（图鉴按势力/生物/物品/技能分组时使用）。
  final Widget? leading;
  final bool initiallyExpanded;

  @override
  State<CollapsibleListGroup> createState() => _CollapsibleListGroupState();
}

class _CollapsibleListGroupState extends State<CollapsibleListGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollapsibleListGroupHeader(
          title: widget.title,
          count: widget.count,
          expanded: _expanded,
          leading: widget.leading,
          onTap: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}
