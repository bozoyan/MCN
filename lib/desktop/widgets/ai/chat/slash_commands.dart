// 职责: 聊天输入框 slash commands 面板 — 渲染可扩展分段的悬浮命令菜单并支持点击选择命令。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/agent_management/novel_editor_subagent_nav.dart
//   lib/shared/models/subagent.dart
//   lib/shared/localization/locale_keys.dart
import 'package:flutter/material.dart';

import '../../../../shared/theme/theme.dart';

class SlashCommandItem {
  const SlashCommandItem({
    required this.id,
    required this.command,
    required this.description,
    required this.insertText,
    this.icon = RevericIcons.smart_toy_outlined,
  });

  final String id;
  final String command;
  final String description;
  final String insertText;
  final String icon;
}

class SlashCommandSection {
  const SlashCommandSection({
    required this.id,
    this.title,
    required this.items,
  });

  final String id;
  final String? title;
  final List<SlashCommandItem> items;
}

class SlashCommands extends StatelessWidget {
  const SlashCommands({
    super.key,
    required this.sections,
    required this.selectedItemId,
    required this.onSelect,
    this.maxWidth = 500,
    this.maxHeight = 240,
  });

  final List<SlashCommandSection> sections;
  final String? selectedItemId;
  final ValueSetter<SlashCommandItem> onSelect;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final visibleSections = sections
        .where((section) => section.items.isNotEmpty)
        .toList();
    if (visibleSections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        RevericSpacing.md,
        0,
        RevericSpacing.md,
        RevericSpacing.md,
      ),
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.lg,
            RevericSpacing.lg,
            RevericSpacing.lg,
            RevericSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < visibleSections.length; i++) ...[
                _SlashCommandSectionView(
                  section: visibleSections[i],
                  selectedItemId: selectedItemId,
                  onSelect: onSelect,
                ),
                if (i < visibleSections.length - 1)
                  const SizedBox(height: RevericSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SlashCommandSectionView extends StatelessWidget {
  const _SlashCommandSectionView({
    required this.section,
    required this.selectedItemId,
    required this.onSelect,
  });

  final SlashCommandSection section;
  final String? selectedItemId;
  final ValueSetter<SlashCommandItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.sm,
              0,
              RevericSpacing.sm,
              RevericSpacing.sm,
            ),
            child: Text(
              section.title!,
              style: typo.uiSemibold.copyWith(color: colors.textSubtle),
            ),
          ),
        for (final item in section.items)
          _SlashCommandItemView(
            item: item,
            isSelected: item.id == selectedItemId,
            onTap: () => onSelect(item),
          ),
      ],
    );
  }
}

class _SlashCommandItemView extends StatelessWidget {
  const _SlashCommandItemView({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final SlashCommandItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xxs),
      child: Material(
        color: isSelected ? colors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.hover,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.md,
            ),
            child: Row(
              children: [
                RevericIcon(
                  item.icon,
                  size: 16,
                  color: isSelected ? colors.accent : colors.textSubtle,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  item.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (isSelected ? typo.uiSemibold : typo.ui).copyWith(
                    color: isSelected
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.ui.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
