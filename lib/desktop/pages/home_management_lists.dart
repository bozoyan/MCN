// 职责: Home AI 管理列表页 — 以卡片网格展示 Prompt 与快捷方式。
// 关联文件:
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/agent_management/home_management_cards.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_context_menu.dart';
import '../../shared/components/reveric_search_field.dart';
import '../../shared/components/reveric_switch.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/models/ai_shortcut_action.dart';
import '../../shared/providers/ai_shortcut_action_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../widgets/agent_management/home_management_cards.dart';

bool _matches(String query, List<String> haystacks) {
  if (query.isEmpty) {
    return true;
  }
  for (final value in haystacks) {
    if (value.toLowerCase().contains(query)) {
      return true;
    }
  }
  return false;
}

class HomeShortcutActionGridPage extends HookConsumerWidget {
  const HomeShortcutActionGridPage({
    super.key,
    required this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    required this.onOpen,
    required this.onCreate,
  });

  final GlobalKey headerGestureExclusionKey;
  final double headerTrailingInset;
  final ValueChanged<AiShortcutActionDefinition> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsAsync = ref.watch(aiShortcutActionsProvider);
    final search = useDebouncedSearch();

    return HomeManagementScaffold(
      headerGestureExclusionKey: headerGestureExclusionKey,
      headerTrailingInset: headerTrailingInset,
      icon: RevericIcons.rocket_launch_outlined,
      titleKey: LocaleKeys.agentShortcutTitle,
      createLabelKey: LocaleKeys.commonCreate,
      onCreate: onCreate,
      child: actionsAsync.when(
        loading: () => const HomeManagementLoadingState(),
        error: (_, _) => HomeManagementErrorState(
          message: context.t(LocaleKeys.commonLoadFailed),
        ),
        data: (actions) {
          if (actions.isEmpty) {
            return HomeManagementEmptyState(
              icon: RevericIcons.rocket_launch_outlined,
              emptyKey: LocaleKeys.agentShortcutEmpty,
              createLabelKey: LocaleKeys.commonCreate,
              onCreate: onCreate,
            );
          }
          final filtered = actions
              .where((a) => _matches(search.query, [a.name, a.prompt]))
              .toList(growable: false);
          return HomeManagementGrid(
            subtitleKey: LocaleKeys.agentShortcutSubtitle,
            sectionTitleKey: LocaleKeys.agentShortcutTitle,
            itemCount: filtered.length,
            searchController: search.controller,
            searchHintKey: LocaleKeys.commonSearch,
            searchActive: search.active,
            createLabelKey: LocaleKeys.commonCreate,
            onCreate: onCreate,
            mainAxisExtent: 250,
            cards: [
              for (final action in filtered)
                _ShortcutActionCard(
                  key: ValueKey('home_shortcut_action_card_${action.id}'),
                  action: action,
                  onOpen: () => onOpen(action),
                ),
            ],
          );
        },
      ),
    );
  }
}

final _log = AppLogger.forModule('HomeManagementLists');

class _ShortcutActionCard extends ConsumerWidget {
  const _ShortcutActionCard({
    super.key,
    required this.action,
    required this.onOpen,
  });

  final AiShortcutActionDefinition action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Future<void> onToggleEnabled(bool enabled) async {
      try {
        await ref
            .read(aiShortcutActionsProvider.notifier)
            .updateAction(action.copyWith(enabled: enabled));
      } catch (error, stackTrace) {
        _log.error(
          'toggle shortcut action enabled failed id=${action.id} enabled=$enabled',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      }
    }

    Future<void> onDelete() async {
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(
          LocaleKeys.agentShortcutDeleteConfirm,
          namedArgs: {'name': action.name},
        ),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      try {
        await ref
            .read(aiShortcutActionsProvider.notifier)
            .deleteAction(action.id);
      } catch (error, stackTrace) {
        _log.error(
          'delete shortcut action failed id=${action.id}',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonDeleteFailed))),
          );
        }
      }
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        hoverColor: colors.hover,
        child: Container(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.xl),
            border: Border.all(color: colors.borderInput),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HomeManagementIconBadge(
                    icon: RevericIcons.rocket_launch_outlined,
                  ),
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.name.isEmpty
                              ? context.t(LocaleKeys.commonUntitled)
                              : action.name,
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: RevericSpacing.xs),
                        _ShortcutActionKindTag(isBuiltin: action.isBuiltin),
                      ],
                    ),
                  ),
                  _ShortcutActionMenu(
                    onOpen: onOpen,
                    onDelete: onDelete,
                    canDelete: !action.isBuiltin,
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.lg),
              Expanded(
                child: Text(
                  action.prompt,
                  style: typo.uiSmall.copyWith(
                    color: colors.textMuted,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: RevericSpacing.lg),
              Divider(height: RevericSizes.dividerThickness),
              const SizedBox(height: RevericSpacing.md),
              Row(
                children: [
                  const Spacer(),
                  RevericSwitch(
                    value: action.enabled,
                    onChanged: (enabled) => unawaited(onToggleEnabled(enabled)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutActionKindTag extends StatelessWidget {
  const _ShortcutActionKindTag({required this.isBuiltin});

  final bool isBuiltin;

  @override
  Widget build(BuildContext context) {
    return HomeManagementMetaTag(
      icon: isBuiltin
          ? RevericIcons.check_circle
          : RevericIcons.edit_outlined,
      label: context.t(
        isBuiltin
            ? LocaleKeys.agentShortcutBuiltin
            : LocaleKeys.agentShortcutCustom,
      ),
      tone: isBuiltin
          ? HomeManagementTagTone.accent
          : HomeManagementTagTone.neutral,
    );
  }
}

class _ShortcutActionMenu extends StatelessWidget {
  const _ShortcutActionMenu({
    required this.onOpen,
    required this.onDelete,
    required this.canDelete,
  });

  final VoidCallback onOpen;
  final Future<void> Function() onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Builder(
      builder: (buttonContext) => Tooltip(
        message: context.t(LocaleKeys.commonMoreActions),
        child: InkWell(
          onTap: () {
            final renderBox = buttonContext.findRenderObject() as RenderBox;
            final origin = renderBox.localToGlobal(Offset.zero);
            unawaited(
              showRevericContextMenu(
                context: context,
                position: Offset(origin.dx, origin.dy + renderBox.size.height),
                entries: [
                  RevericMenuItem(
                    icon: RevericIcons.edit_outlined,
                    iconColor: colors.textSecondary,
                    label: context.t(LocaleKeys.commonEdit),
                    onTap: onOpen,
                  ),
                  if (canDelete) ...[
                    const RevericMenuDivider(),
                    RevericMenuItem(
                      icon: RevericIcons.delete_outline,
                      iconColor: colors.warningText,
                      labelColor: colors.warningText,
                      label: context.t(LocaleKeys.commonDelete),
                      onTap: () => unawaited(onDelete()),
                    ),
                  ],
                ],
              ),
            );
          },
          borderRadius: BorderRadius.circular(RevericRadius.small),
          child: Padding(
            padding: const EdgeInsets.all(RevericSpacing.xs),
            child: RevericIcon(
              RevericIcons.more_horiz,
              size: 18,
              color: colors.textSubtle,
            ),
          ),
        ),
      ),
    );
  }
}
