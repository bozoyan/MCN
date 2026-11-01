// 职责: 桌面端技能来源卡片(技能库 / 官方目录 / 广场) — 统一 head/desc/meta/foot 布局;
//   配套按行 intrinsic 网格,同行底栏对齐且避免固定宽高比撑出大块空白。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_panel.dart
//   lib/desktop/features/agent_skills/official_catalog_tab.dart
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/directory-structure.md
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/promo_badge.dart';

/// 技能来源卡片次要动作(如技能库「上传」)。
class AgentSkillSourceCardSecondaryAction {
  const AgentSkillSourceCardSecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;
}

/// 技能来源卡片主动作(如「安装」)。
class AgentSkillSourceCardPrimaryAction {
  const AgentSkillSourceCardPrimaryAction({
    this.onPressed,
    this.labelKey = LocaleKeys.agentSkillInstall,
    this.icon = RevericIcons.download,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final String labelKey;
  final String icon;
  final bool isLoading;
}

/// 技能库 / 官方目录 / 广场共用的来源卡片。
///
/// 布局对齐 designs `SkSourceCard`:
/// head(badge+title+version) → desc → meta(类别+tags) → [Spacer] → foot。
/// 请配合 [AgentSkillSourceCardGrid] 使用:行高取同行最高卡片,
/// [Spacer] 只吸收「同行高度差」,不会被固定宽高比撑出大块空白。
class AgentSkillSourceCard extends StatelessWidget {
  const AgentSkillSourceCard({
    super.key,
    required this.badgeIcon,
    required this.name,
    required this.description,
    this.version,
    this.badgeLabel,
    this.category = '',
    this.tags = const <String>[],
    this.footerLeading,
    this.updatedAtLabel,
    this.onTap,
    this.secondary,
    this.primary,
  });

  final String badgeIcon;
  final String name;
  final String description;

  /// 不含 `v` 前缀的版本号;null 时不显示版本 chip。
  final Object? version;

  /// 目录条目中的展示徽章文案（如「推荐」）；空则不显示。
  final String? badgeLabel;
  final String category;
  final List<String> tags;

  /// 脚栏左侧已本地化文案(如作者);优先于 [updatedAtLabel]。
  final String? footerLeading;

  /// 已格式化的相对时间(如「刚刚」);null/空则不显示「更新于」。
  final String? updatedAtLabel;

  /// 点击卡片主体打开详情;底栏按钮各自处理,不依赖此回调。
  final VoidCallback? onTap;
  final AgentSkillSourceCardSecondaryAction? secondary;
  final AgentSkillSourceCardPrimaryAction? primary;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final leading = footerLeading?.trim() ?? '';
    final stamp = updatedAtLabel?.trim() ?? '';
    final footerText = leading.isNotEmpty
        ? leading
        : stamp.isNotEmpty
        ? context.t(LocaleKeys.agentSkillUpdatedAt, namedArgs: {'time': stamp})
        : '';
    final versionLabel = version == null ? null : 'v$version';
    final radius = BorderRadius.circular(RevericRadius.large);

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.borderInput),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x2l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                    ),
                    child: RevericIcon(
                      badgeIcon,
                      size: 18,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: Text(
                      name,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badgeLabel != null && badgeLabel!.trim().isNotEmpty) ...[
                    const SizedBox(width: RevericSpacing.sm),
                    RevericPromoBadge(badgeLabel!.trim()),
                  ],
                  if (versionLabel != null) ...[
                    const SizedBox(width: RevericSpacing.sm),
                    AgentSkillSourceTag(
                      icon: RevericIcons.git_fork,
                      label: versionLabel,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: RevericSpacing.lg),
              // 描述按内容高度(最多 2 行),不吃掉剩余空间。
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(
                  color: colors.textMuted,
                  height: 1.55,
                ),
              ),
              if (category.isNotEmpty || tags.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.lg),
                Wrap(
                  spacing: RevericSpacing.sm,
                  runSpacing: RevericSpacing.xxs,
                  children: [
                    if (category.isNotEmpty)
                      AgentSkillSourceTag(
                        icon: RevericIcons.label_outline,
                        label: category,
                      ),
                    for (final t in tags) AgentSkillSourceTag(label: t),
                  ],
                ),
              ],
              // 剩余高度压到脚栏上方,保持网格内卡片底栏齐平。
              const Spacer(),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: RevericSpacing.lg),
                  child: Row(
                    children: [
                      if (footerText.isNotEmpty)
                        Expanded(
                          child: Text(
                            footerText,
                            style: typo.uiTiny.copyWith(
                              color: colors.textSubtle,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const Spacer(),
                      if (secondary != null)
                        TextButton(
                          onPressed: secondary!.onPressed,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.textSecondary,
                            minimumSize: const Size(
                              0,
                              RevericSizes.buttonHeightSm,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: RevericSpacing.sm,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RevericIcon(
                                secondary!.icon,
                                size: 14,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: RevericSpacing.xs),
                              Text(secondary!.label),
                            ],
                          ),
                        ),
                      if (primary != null) ...[
                        if (secondary != null)
                          const SizedBox(width: RevericSpacing.xs),
                        OutlinedButton(
                          onPressed: primary!.isLoading
                              ? null
                              : primary!.onPressed,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary!.onPressed == null
                                ? colors.textSubtle
                                : colors.textSecondary,
                            side: BorderSide(color: colors.borderInput),
                            minimumSize: const Size(
                              0,
                              RevericSizes.buttonHeightSm,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: RevericSpacing.lg,
                            ),
                          ),
                          child: primary!.isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.textMuted,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RevericIcon(
                                      primary!.icon,
                                      size: 14,
                                      color: primary!.onPressed == null
                                          ? colors.textSubtle
                                          : colors.textSecondary,
                                    ),
                                    const SizedBox(width: RevericSpacing.xs),
                                    Text(context.t(primary!.labelKey)),
                                  ],
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 来源卡片上的小型标签 chip。
class AgentSkillSourceTag extends StatelessWidget {
  const AgentSkillSourceTag({super.key, this.icon, required this.label});

  final String? icon;
  final String label;

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
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: colors.borderInput),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            RevericIcon(icon!, size: 12, color: colors.textMuted),
            const SizedBox(width: 4),
          ],
          Text(label, style: typo.uiTiny.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

/// 按行 intrinsic 等高的来源卡片网格。
///
/// 行高 = 该行最高卡片的内容高度(不再用固定 childAspectRatio),
/// 同行卡片 stretch 后底栏对齐;空白只等于同行内容高度差。
class AgentSkillSourceCardGrid extends StatelessWidget {
  const AgentSkillSourceCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxCrossAxisExtent = 360,
    this.mainAxisSpacing = RevericSpacing.x3l,
    this.crossAxisSpacing = RevericSpacing.x3l,
    this.padding = const EdgeInsetsDirectional.fromSTEB(
      RevericSpacing.x5l,
      RevericSpacing.x3l,
      RevericSpacing.x5l,
      RevericSpacing.x5l,
    ),
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final available = math.max(
          0.0,
          constraints.maxWidth - resolvedPadding.horizontal,
        );
        final crossAxisCount = math.max(
          1,
          ((available + crossAxisSpacing) /
                  (maxCrossAxisExtent + crossAxisSpacing))
              .floor(),
        );
        final rowCount = itemCount == 0
            ? 0
            : ((itemCount + crossAxisCount - 1) / crossAxisCount).floor();

        return ListView.separated(
          padding: resolvedPadding,
          itemCount: rowCount,
          separatorBuilder: (_, _) => SizedBox(height: mainAxisSpacing),
          itemBuilder: (context, rowIndex) {
            final start = rowIndex * crossAxisCount;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var slot = 0; slot < crossAxisCount; slot++) ...[
                    if (slot > 0) SizedBox(width: crossAxisSpacing),
                    Expanded(
                      child: start + slot < itemCount
                          ? itemBuilder(context, start + slot) ??
                                const SizedBox.shrink()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
