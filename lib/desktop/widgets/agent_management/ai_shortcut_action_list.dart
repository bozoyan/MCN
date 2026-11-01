// 职责: AI 快捷方式列表 — 在 Home AI 分组中展示全局快捷方式并支持选择。
// 关联文件:
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/desktop/widgets/agent_management/ai_shortcut_action_edit_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_shortcut_action.dart';
import '../../../shared/providers/ai_shortcut_action_providers.dart';
import '../../../shared/theme/theme.dart';

class AiShortcutActionList extends ConsumerWidget {
  const AiShortcutActionList({
    super.key,
    this.onSelectAction,
    this.selectedActionId,
    this.showHeader = true,
    this.showCreateButton = true,
  });

  final ValueChanged<AiShortcutActionDefinition>? onSelectAction;
  final String? selectedActionId;
  final bool showHeader;
  final bool showCreateButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final actions =
        ref.watch(aiShortcutActionsProvider).asData?.value ??
        const <AiShortcutActionDefinition>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x2l,
              vertical: RevericSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  context.t(LocaleKeys.agentShortcutTitle),
                  style: typo.uiTinySemibold.copyWith(
                    color: colors.textSubtle,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (showCreateButton)
                  InkWell(
                    onTap: () => onSelectAction?.call(_newShortcutDraft()),
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: RevericIcon(
                      RevericIcons.add,
                      size: 16,
                      color: colors.textSubtle,
                    ),
                  ),
              ],
            ),
          ),
        if (actions.isNotEmpty)
          ...actions.map(
            (action) => _buildActionItem(
              context,
              action,
              isSelected: selectedActionId == action.id,
              onSelect: onSelectAction,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x2l,
              vertical: RevericSpacing.lg,
            ),
            child: Text(
              context.t(LocaleKeys.agentShortcutEmpty),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }

  AiShortcutActionDefinition _newShortcutDraft() {
    return AiShortcutActionDefinition(
      id: '__new__${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      prompt: '',
      locations: const <AiShortcutActionLocation>[],
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    AiShortcutActionDefinition action, {
    required bool isSelected,
    required ValueChanged<AiShortcutActionDefinition>? onSelect,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: isSelected ? colors.selected : Colors.transparent,
      child: InkWell(
        onTap: onSelect != null ? () => onSelect(action) : null,
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.xs,
          ),
          child: Row(
            children: [
              RevericIcon(
                RevericIcons.rocket_launch_outlined,
                size: 16,
                color: isSelected ? colors.accent : colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.name.isEmpty
                          ? context.t(LocaleKeys.commonUntitled)
                          : action.name,
                      style: (isSelected ? typo.uiSemibold : typo.ui).copyWith(
                        color: isSelected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      action.isBuiltin
                          ? context.t(LocaleKeys.agentShortcutBuiltin)
                          : context.t(LocaleKeys.agentShortcutCustom),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
