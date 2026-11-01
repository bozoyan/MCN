// 职责: AI 功能首次使用引导对话框与按需触发函数，展示功能用途和使用方法。
// 关联文件:
//   lib/desktop/features/council/panel.dart
//   lib/desktop/features/monologue/panel.dart
//   lib/desktop/features/theater/panel.dart
//   lib/desktop/features/roleplay/panel.dart
//   lib/desktop/widgets/agent_management/agent_rule_edit_panel.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/theme/theme.dart';

enum FeatureOnboardingType {
  council(
    titleKey: LocaleKeys.aiFeatureOnboardingCouncilTitle,
    introKey: LocaleKeys.aiFeatureOnboardingCouncilIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingCouncilHowTo,
    icon: RevericIcons.groups_outlined,
    featureIcon: RevericIcons.groups_outlined,
  ),
  monologue(
    titleKey: LocaleKeys.aiFeatureOnboardingMonologueTitle,
    introKey: LocaleKeys.aiFeatureOnboardingMonologueIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingMonologueHowTo,
    icon: RevericIcons.psychology_outlined,
    featureIcon: RevericIcons.psychology_outlined,
  ),
  theater(
    titleKey: LocaleKeys.aiFeatureOnboardingTheaterTitle,
    introKey: LocaleKeys.aiFeatureOnboardingTheaterIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingTheaterHowTo,
    icon: RevericIcons.theater_comedy_outlined,
    featureIcon: RevericIcons.theater_comedy_outlined,
  ),
  roleplay(
    titleKey: LocaleKeys.aiFeatureOnboardingRoleplayTitle,
    introKey: LocaleKeys.aiFeatureOnboardingRoleplayIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingRoleplayHowTo,
    icon: RevericIcons.directions_run_rounded,
    featureIcon: RevericIcons.directions_run_rounded,
  ),
  agentRules(
    titleKey: LocaleKeys.aiFeatureOnboardingAgentRulesTitle,
    introKey: LocaleKeys.aiFeatureOnboardingAgentRulesIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingAgentRulesHowTo,
    icon: RevericIcons.rule_outlined,
    featureIcon: RevericIcons.shield_check,
  ),
  avatar_generation(
    titleKey: LocaleKeys.aiFeatureOnboardingAvatarGenerationTitle,
    introKey: LocaleKeys.aiFeatureOnboardingAvatarGenerationIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingAvatarGenerationHowTo,
    icon: RevericIcons.person_outline,
    featureIcon: RevericIcons.image,
  ),
  outline_craft(
    titleKey: LocaleKeys.aiFeatureOnboardingOutlineCraftTitle,
    introKey: LocaleKeys.aiFeatureOnboardingOutlineCraftIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingOutlineCraftHowTo,
    icon: RevericIcons.account_tree_outlined,
    featureIcon: RevericIcons.format_list_bulleted,
  ),
  feature_usage(
    titleKey: LocaleKeys.aiFeatureOnboardingFeatureUsageTitle,
    introKey: LocaleKeys.aiFeatureOnboardingFeatureUsageIntro,
    howToKey: LocaleKeys.aiFeatureOnboardingFeatureUsageHowTo,
    icon: RevericIcons.lightbulb_outline,
    featureIcon: RevericIcons.lightbulb_outline,
  );

  const FeatureOnboardingType({
    required this.titleKey,
    required this.introKey,
    required this.howToKey,
    required this.icon,
    required this.featureIcon,
  });

  final String titleKey;
  final String introKey;
  final String howToKey;
  final String icon;
  final String featureIcon;

  String get storageKey => 'feature_onboarding.$name';
}

Future<void> showFeatureOnboardingDialog(
  BuildContext context,
  FeatureOnboardingType type,
) async {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: colors.textPrimary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          side: BorderSide(color: colors.borderSubtle),
        ),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x3l,
                  RevericSpacing.x2l,
                  RevericSpacing.x2l,
                  RevericSpacing.xl,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(RevericRadius.large),
                  ),
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _FeatureHeroIcon(icon: type.icon),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: RevericIcon(
                            RevericIcons.close,
                            size: 18,
                            color: colors.textMuted,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          splashRadius: 16,
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dialogContext.t(type.titleKey),
                        style: typo.heading2.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(RevericSpacing.x3l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogContext.t(type.introKey),
                      style: typo.ui.copyWith(
                        color: colors.textSecondary,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    _FeatureCard(
                      icon: type.featureIcon,
                      title: dialogContext.t(type.titleKey),
                      description: dialogContext.t(type.howToKey),
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textSecondary,
                              side: BorderSide(color: colors.borderSubtle),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  RevericRadius.button,
                                ),
                              ),
                              minimumSize: const Size(
                                0,
                                RevericSizes.buttonHeight,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: RevericSizes.buttonPaddingH,
                              ),
                              textStyle: typo.uiSemibold,
                            ),
                            child: Text(
                              dialogContext.t(LocaleKeys.commonCancel),
                            ),
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  dialogContext.t(
                                    LocaleKeys.aiFeatureOnboardingDialogGotIt,
                                  ),
                                ),
                                const SizedBox(width: RevericSpacing.xs),
                                RevericIcon(
                                  RevericIcons.arrow_forward,
                                  size: 14,
                                  color: colors.onAccent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> triggerFeatureOnboardingIfNeeded(
  BuildContext context,
  WidgetRef ref,
  FeatureOnboardingType type,
) async {
  if (!context.mounted) return;
  final db = ref.read(appDatabaseProvider);
  final existing = await (db.select(
    db.featureUsages,
  )..where((t) => t.featureId.equals(type.storageKey))).getSingleOrNull();
  if (existing != null || !context.mounted) return;
  final now = DateTime.now();
  await db
      .into(db.featureUsages)
      .insert(
        FeatureUsagesCompanion.insert(
          featureId: type.storageKey,
          firstUsedAt: now,
          lastUsedAt: now,
        ),
      );
  if (!context.mounted) return;
  await showFeatureOnboardingDialog(context, type);
}

class _FeatureHeroIcon extends StatelessWidget {
  const _FeatureHeroIcon({required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.accentWarm.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.accentWarm.withValues(alpha: 0.24)),
      ),
      child: Center(
        child: RevericIcon(icon, size: 24, color: colors.accentWarm),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final String icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.accentWarm.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: Center(
              child: RevericIcon(icon, size: 18, color: colors.accentWarm),
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: RevericSpacing.xs),
                Text(
                  description,
                  style: typo.uiSmall.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
