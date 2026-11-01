// 职责: 小说编辑器侧边栏的 Agent Profile 导航列表 — 作为 primary agent 提示词入口。
// 关联文件:
//   lib/shared/providers/agent_profile_providers.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_profile.dart';
import '../../../shared/providers/agent_profile_providers.dart';
import '../../../shared/theme/theme.dart';

String _getAgentDisplayName(AgentProfile profile) {
  return profile.name;
}

class NovelEditorAgentNav extends HookConsumerWidget {
  const NovelEditorAgentNav({
    super.key,
    this.novelId,
    this.onSelectProfile,
    this.selectedProfileId,
  });

  final String? novelId;
  final ValueChanged<AgentProfile>? onSelectProfile;
  final String? selectedProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isExpanded = useState(false);

    final mergedProfiles = novelId != null
        ? ref.watch(mergedAgentProfilesProvider(novelId: novelId))
        : <AgentProfile>[];

    final totalCount = mergedProfiles.length;

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
                  RevericIcons.account_tree_outlined,
                  size: 18,
                  color: colors.accent,
                ),
                const SizedBox(width: RevericSpacing.md),
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.agentTitle),
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  ),
                ),
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
          ...mergedProfiles.map(
            (profile) => _buildProfileItem(
              context,
              profile,
              isGlobal: profile.scope == AgentProfileScope.global,
              isSelected: selectedProfileId == profile.id,
              onSelect: onSelectProfile,
            ),
          ),
          if (mergedProfiles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: RevericSpacing.x2l + RevericSpacing.x2l,
                right: RevericSpacing.x2l,
                top: RevericSpacing.xs,
                bottom: RevericSpacing.xs,
              ),
              child: Text(
                context.t(LocaleKeys.agentEmpty),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildProfileItem(
    BuildContext context,
    AgentProfile profile, {
    required bool isGlobal,
    required bool isSelected,
    required ValueChanged<AgentProfile>? onSelect,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: isSelected ? colors.selected : Colors.transparent,
      child: InkWell(
        onTap: onSelect != null ? () => onSelect(profile) : null,
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
                RevericIcons.account_tree_outlined,
                size: 16,
                color: isSelected ? colors.accent : colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  _getAgentDisplayName(profile),
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
                    context.t(LocaleKeys.agentGlobal),
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
