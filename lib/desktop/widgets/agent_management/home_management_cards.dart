// 职责: Home 管理入口卡片布局 — 提供列表页标题栏、卡片网格、创建卡片与状态占位。
// 关联文件:
//   lib/desktop/pages/home_management_lists.dart
//   lib/desktop/pages/home.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/dotted_border_box.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../desktop_window_frame.dart';

class HomeManagementScaffold extends ConsumerWidget {
  const HomeManagementScaffold({
    super.key,
    required this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    required this.icon,
    required this.titleKey,
    required this.child,
    this.createLabelKey,
    this.onCreate,
    this.onBack,
    this.secondaryAction,
  });

  final GlobalKey headerGestureExclusionKey;
  final double headerTrailingInset;
  final String icon;
  final String titleKey;
  final String? createLabelKey;
  final VoidCallback? onCreate;
  final VoidCallback? onBack;
  final Widget? secondaryAction;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    return Container(
      color: appScaffoldBackgroundColor(colors, appBackgroundActive),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: headerGestureExclusionKey,
            height: DesktopWindowFrame.titleBarHeight,
            padding: EdgeInsets.only(
              left: RevericSpacing.x2l,
              right: RevericSpacing.lg + headerTrailingInset,
            ),
            child: Row(
              children: [
                if (onBack != null) ...[
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: onBack,
                    icon: RevericIcon(
                      RevericIcons.arrow_back,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                ],
                RevericIcon(icon, size: 18, color: colors.accent),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    context.t(titleKey),
                    style: typo.heading2.copyWith(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (secondaryAction != null) ...[
                  secondaryAction!,
                  const SizedBox(width: RevericSpacing.sm),
                ],
                if (onCreate != null && createLabelKey != null)
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const RevericIcon(RevericIcons.add, size: 16),
                    label: Text(context.t(createLabelKey!)),
                  ),
              ],
            ),
          ),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class HomeManagementGrid extends StatelessWidget {
  const HomeManagementGrid({
    super.key,
    required this.sectionTitleKey,
    required this.itemCount,
    required this.cards,
    this.subtitleKey,
    this.searchController,
    this.searchHintKey,
    this.searchActive = false,
    this.createLabelKey,
    this.onCreate,
    this.mainAxisExtent = 150,
  });

  final String sectionTitleKey;
  final int itemCount;
  final List<Widget> cards;

  /// 列表页标题下的一句话说明；为 null 时不展示。
  final String? subtitleKey;

  /// 提供后在分区标签右侧展示搜索框；过滤逻辑由调用方负责（须 debounce）。
  final TextEditingController? searchController;
  final String? searchHintKey;

  /// 当前是否处于搜索过滤态：隐藏新建卡，并在无匹配时展示无结果占位。
  final bool searchActive;

  final String? createLabelKey;
  final VoidCallback? onCreate;

  /// 单个卡片的主轴高度；专家团风格卡片可设为 250，紧凑卡片保持默认 150。
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final showCreateCard =
        onCreate != null && createLabelKey != null && !searchActive;
    final children = [
      ...cards,
      if (showCreateCard)
        HomeCreateManagementCard(labelKey: createLabelKey!, onTap: onCreate!),
    ];

    return CustomScrollView(
      slivers: [
        if (subtitleKey != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x4l,
              RevericSpacing.x2l,
              RevericSpacing.x4l,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                context.t(subtitleKey!),
                style: typo.uiSmall.copyWith(
                  color: colors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            RevericSpacing.x4l,
            subtitleKey != null ? RevericSpacing.lg : RevericSpacing.x2l,
            RevericSpacing.x4l,
            RevericSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  context.t(sectionTitleKey),
                  style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  '· $itemCount',
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
                if (searchController != null && searchHintKey != null) ...[
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    child: RevericSearchField(
                      controller: searchController!,
                      hint: context.t(searchHintKey!),
                      height: 34,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (cards.isEmpty && searchActive)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _ManagementNoResults(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x4l,
              0,
              RevericSpacing.x4l,
              RevericSpacing.x4l,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: mainAxisExtent,
                crossAxisSpacing: RevericSpacing.x2l,
                mainAxisSpacing: RevericSpacing.x2l,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => children[index],
                childCount: children.length,
              ),
            ),
          ),
      ],
    );
  }
}

/// 搜索无匹配时的占位。
class _ManagementNoResults extends StatelessWidget {
  const _ManagementNoResults();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(
            RevericIcons.search,
            size: 28,
            color: colors.textSubtle,
          ),
          const SizedBox(height: RevericSpacing.lg),
          Text(
            context.t(LocaleKeys.commonNoResults),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class HomeManagementCard extends StatelessWidget {
  const HomeManagementCard({
    super.key,
    required this.leading,
    required this.title,
    required this.description,
    required this.meta,
    required this.onTap,
    this.onDelete,
    this.deleteTitle,
    this.deleteMessage,
  });

  final Widget leading;
  final String title;
  final String description;
  final List<Widget> meta;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final String? deleteTitle;
  final String? deleteMessage;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final canDelete =
        onDelete != null && deleteTitle != null && deleteMessage != null;

    Future<void> confirmDelete() async {
      final shouldDelete = await showConfirmDialog(
        context,
        title: deleteTitle!,
        message: deleteMessage!,
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
      );
      if (context.mounted && shouldDelete) {
        await onDelete!();
      }
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        hoverColor: colors.hover,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderSubtle),
          ),
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  leading,
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: Text(
                      title,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  if (canDelete)
                    Tooltip(
                      message: context.t(LocaleKeys.commonDelete),
                      child: InkWell(
                        onTap: confirmDelete,
                        borderRadius: BorderRadius.circular(
                          RevericRadius.small,
                        ),
                        hoverColor: colors.hover,
                        child: Padding(
                          padding: const EdgeInsets.all(RevericSpacing.xs),
                          child: RevericIcon(
                            RevericIcons.delete_outline,
                            size: 18,
                            color: colors.textSubtle,
                          ),
                        ),
                      ),
                    )
                  else
                    RevericIcon(
                      RevericIcons.keyboard_arrow_right,
                      size: 18,
                      color: colors.textSubtle,
                    ),
                ],
              ),
              const SizedBox(height: RevericSpacing.lg),
              Expanded(
                child: Text(
                  description,
                  style: typo.uiSmall.copyWith(
                    color: colors.textMuted,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: RevericSpacing.lg),
              Wrap(
                spacing: RevericSpacing.sm,
                runSpacing: RevericSpacing.xs,
                children: meta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeManagementIconBadge extends StatelessWidget {
  const HomeManagementIconBadge({super.key, required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: RevericIcon(icon, size: 18, color: colors.accent),
    );
  }
}

/// meta 标签的语气：描述类用 neutral，状态类用 accent/success/muted 着色。
enum HomeManagementTagTone { neutral, accent, success, muted }

class HomeManagementMetaTag extends StatelessWidget {
  const HomeManagementMetaTag({
    super.key,
    required this.icon,
    required this.label,
    this.tone = HomeManagementTagTone.neutral,
  });

  final String icon;
  final String label;
  final HomeManagementTagTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final Color foreground = switch (tone) {
      HomeManagementTagTone.neutral => colors.textMuted,
      HomeManagementTagTone.accent => colors.accent,
      HomeManagementTagTone.success => colors.success,
      HomeManagementTagTone.muted => colors.textSubtle,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(icon, size: 12, color: foreground),
          const SizedBox(width: RevericSpacing.xxs),
          Text(label, style: typo.uiTiny.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

class HomeCreateManagementCard extends StatelessWidget {
  const HomeCreateManagementCard({
    super.key,
    required this.labelKey,
    required this.onTap,
  });

  final String labelKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: colors.surfaceDim.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        hoverColor: colors.hover,
        child: DottedBorderBox(
          color: colors.borderSubtle,
          borderRadius: RevericRadius.large,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: RevericIcon(
                      RevericIcons.add,
                      size: 20,
                      color: colors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.md),
                Text(
                  context.t(labelKey),
                  style: typo.uiSemibold.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeManagementEmptyState extends StatelessWidget {
  const HomeManagementEmptyState({
    super.key,
    required this.icon,
    required this.emptyKey,
    this.createLabelKey,
    this.onCreate,
  });

  final String icon;
  final String emptyKey;
  final String? createLabelKey;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RevericPlaceholder.empty(
        icon: icon,
        title: context.t(emptyKey),
        action: onCreate != null && createLabelKey != null
            ? RevericButton.primary(
                label: context.t(createLabelKey!),
                icon: RevericIcons.add,
                onPressed: onCreate,
              )
            : null,
      ),
    );
  }
}

class HomeManagementLoadingState extends StatelessWidget {
  const HomeManagementLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Center(child: CircularProgressIndicator(color: colors.accent));
  }
}

class HomeManagementErrorState extends StatelessWidget {
  const HomeManagementErrorState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: RevericPlaceholder.error(title: message));
  }
}
