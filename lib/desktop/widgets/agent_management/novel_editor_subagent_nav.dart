// 职责: 小说编辑器侧边栏的智能体导航列表 — 可折叠；当前仅管理全局 SubAgent。
// 关联文件:
//   lib/shared/providers/subagent_providers.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/subagent.dart';
import '../../../shared/providers/subagent_providers.dart';
import '../../../shared/theme/theme.dart';

class NovelEditorSubAgentNav extends HookConsumerWidget {
  const NovelEditorSubAgentNav({
    super.key,
    this.novelId,
    this.onSelectAgent,
    this.selectedAgentId,
  });

  final String? novelId;
  final ValueChanged<SubAgent>? onSelectAgent;
  final String? selectedAgentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isExpanded = useState(false);

    final mergedAgents = novelId != null
        ? ref.watch(mergedSubAgentsProvider)
        : <SubAgent>[];
    final visibleAgents = mergedAgents
        .where(isUserVisibleSubAgent)
        .toList(growable: false);

    final totalCount = visibleAgents.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => isExpanded.value = !isExpanded.value,
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x2l,
              vertical: RevericSpacing.sm,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.smart_toy_outlined,
                  size: 18,
                  color: colors.accent,
                ),
                const SizedBox(width: RevericSpacing.md),
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.subagentTitle),
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  ),
                ),
                InkWell(
                  onTap: () {
                    onSelectAgent?.call(
                      SubAgent(
                        id: '__new__${DateTime.now().microsecondsSinceEpoch}',
                        slug: '',
                        name: '',
                        description: '',
                        prompt: '',
                        scope: SubAgentScope.global,
                        sortOrder: 0,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                  child: RevericIcon(
                    RevericIcons.add,
                    size: 16,
                    color: colors.textSubtle,
                  ),
                ),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  '$totalCount',
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
                const SizedBox(width: RevericSpacing.sm),
                RevericIcon(
                  isExpanded.value
                      ? RevericIcons.keyboard_arrow_down
                      : RevericIcons.keyboard_arrow_right,
                  size: 14,
                  color: colors.textSubtle,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded.value) ...[
          ...visibleAgents.map(
            (agent) => _buildAgentItem(
              context,
              agent,
              isGlobal: agent.scope == SubAgentScope.global,
              isSelected: selectedAgentId == agent.id,
              onSelect: onSelectAgent,
            ),
          ),
          if (visibleAgents.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: RevericSpacing.x2l + RevericSpacing.x2l,
                right: RevericSpacing.x2l,
                top: RevericSpacing.xs,
                bottom: RevericSpacing.xs,
              ),
              child: Text(
                context.t(LocaleKeys.subagentEmpty),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAgentItem(
    BuildContext context,
    SubAgent agent, {
    required bool isGlobal,
    required bool isSelected,
    required ValueChanged<SubAgent>? onSelect,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: isSelected ? colors.selected : Colors.transparent,
      child: InkWell(
        onTap: onSelect != null ? () => onSelect(agent) : null,
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.only(
            left: RevericSpacing.x2l + RevericSpacing.x2l,
            right: RevericSpacing.x2l,
            top: RevericSpacing.xs,
            bottom: RevericSpacing.xs,
          ),
          child: Row(
            children: [
              RevericIcon(
                RevericIcons.smart_toy_outlined,
                size: 16,
                color: isSelected ? colors.accent : colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  agent.name,
                  style: (isSelected ? typo.uiSemibold : typo.ui).copyWith(
                    color: isSelected
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isGlobal)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.selected,
                    borderRadius: BorderRadius.circular(RevericRadius.xl),
                  ),
                  child: Text(
                    context.t(LocaleKeys.subagentGlobal),
                    style: typo.uiTiny.copyWith(color: colors.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
