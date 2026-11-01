// 职责: 桌面端首次启动引导页面 — 用户档案设置页（背景插画 + 浮窗卡片），其余默认配置静默应用。
// 关联文件:
//   lib/shared/hooks/use_onboarding_setup.dart
//   lib/shared/utils/avatar_storage.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/localization/locale_keys.dart
//   assets/images/onboarding-background.webp
//   lib/shared/widgets/brand_loader.dart
//   assets/translations/en/onboarding.json
//   assets/translations/zh-CN/onboarding.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/desktop-window-frame.md
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/hooks/use_onboarding_setup.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/theme/theme.dart';
import '../../shared/utils/avatar_storage.dart';
import '../../shared/utils/storage_paths.dart';
import '../../shared/widgets/app_background.dart';
import '../../shared/widgets/brand_loader.dart';
import '../widgets/desktop_window_frame.dart';
import 'home.dart';

final _log = AppLogger.forModule('Onboarding');

const double _kCardWidth = 420;
const double _kContentColumnWidth = 456;
const double _kAvatarSize = 96;
const double _kPrimaryButtonHeight = 52;
const int _kUsernameMaxLength = 20;

class OnboardingPage extends HookConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final setup = useOnboardingSetup(ref);
    final isCreatingDemo = useState(false);
    final showIntro = useState(true);
    final replayRequest = useState(0);

    Future<void> completeOnboarding() async {
      isCreatingDemo.value = true;
      await Future.delayed(const Duration(milliseconds: 50));
      await setup.complete();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const NovelHomePage()),
        );
      }
    }

    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    if (isCreatingDemo.value) {
      return Scaffold(
        backgroundColor: colors.canvas,
        // 保存资料通常很快：先只铺背景色，慢了才淡入 logo，避免一闪而过。
        body: const BrandLoader(
          skipIntro: true,
          showDelay: Duration(milliseconds: 800),
        ),
      );
    }

    return Scaffold(
      backgroundColor: appScaffoldBackgroundColor(colors, appBackgroundActive),
      body: DesktopWindowFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _OnboardingBackground(),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x6l,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kContentColumnWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!showIntro.value) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: _ReplayIntroButton(
                            onPressed: () {
                              replayRequest.value++;
                              showIntro.value = true;
                            },
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.lg),
                      ],
                      const _WelcomeBlock(),
                      const SizedBox(height: RevericSpacing.x3l),
                      _ProfileCard(setup: setup, onSubmit: completeOnboarding),
                    ],
                  ),
                ),
              ),
            ),
            // 入场动画同时覆盖默认模型配置的加载：配置就绪且入场播完后淡出。
            if (showIntro.value)
              BrandLoader(
                key: ValueKey(replayRequest.value),
                done: setup.defaultsReady,
                onExited: () {
                  showIntro.value = false;
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingBackground extends StatelessWidget {
  const _OnboardingBackground();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    const backgroundProvider = AssetImage(
      'assets/images/onboarding-background.webp',
    );
    return ColoredBox(
      color: colors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: backgroundProvider,
            fit: BoxFit.cover,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => ColoredBox(color: colors.canvas),
          ),
          _OnboardingBackgroundScrim(colors: colors),
        ],
      ),
    );
  }
}

class _OnboardingBackgroundScrim extends StatelessWidget {
  const _OnboardingBackgroundScrim({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colors.canvas.withValues(alpha: 0),
                colors.canvas.withValues(alpha: 0.12),
                colors.canvas.withValues(alpha: 0.68),
                colors.canvas.withValues(alpha: 0.9),
              ],
              stops: const [0, 0.48, 0.72, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                colors.canvas.withValues(alpha: 0.24),
                colors.canvas.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplayIntroButton extends StatelessWidget {
  const _ReplayIntroButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: colors.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.play_arrow,
                size: 16,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.onboardingReplayIntro),
                style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends HookWidget {
  const _ProfileCard({required this.setup, required this.onSubmit});

  final OnboardingSetup setup;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final usernameController = setup.nameController;
    final avatarPath = setup.avatarPath;
    useListenable(usernameController);
    useListenable(avatarPath);

    final trimmedName = usernameController.text.trim();
    final nextNameValid = trimmedName.isNotEmpty;

    Future<void> pickAvatar() async {
      if (!setup.defaultsReady) {
        return;
      }
      final result = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          ),
        ],
      );
      if (result == null) {
        return;
      }
      try {
        avatarPath.value = await storeAvatarFile(result.path);
        await setup.saveProfile();
      } catch (error, stackTrace) {
        _log.error(
          'Onboarding avatar selection failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return Container(
      width: _kCardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x4l,
        vertical: RevericSpacing.x4l,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(
          color: colors.accentWarm.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accentWarm.withValues(alpha: 0.14),
            blurRadius: 36,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t(LocaleKeys.onboardingProfileCardTitle),
            textAlign: TextAlign.center,
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.onboardingProfileCardSubtitle),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          Center(
            child: _AvatarPicker(path: avatarPath.value, onTap: pickAvatar),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Text(
            context.t(LocaleKeys.onboardingAvatarUpload),
            textAlign: TextAlign.center,
            style: typo.uiSemibold.copyWith(color: colors.accent),
          ),
          const SizedBox(height: RevericSpacing.xxs),
          Text(
            context.t(LocaleKeys.onboardingAvatarFormatHint),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          Text(
            context.t(LocaleKeys.onboardingUsernameLabel),
            style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.xs),
          _UsernameField(
            controller: usernameController,
            onChanged: () => unawaited(setup.saveProfile()),
            length: trimmedName.length,
          ),
          const SizedBox(height: RevericSpacing.x3l),
          _PrimaryGradientButton(
            label: context.t(LocaleKeys.onboardingGetStarted),
            enabled: nextNameValid,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    // 存储值可能是相对/旧绝对路径；预览统一过 resolveStored 兜底。
    final resolvedPath = RevericPaths.resolveStored(path);
    final hasImage = resolvedPath != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _kAvatarSize + 8,
          height: _kAvatarSize + 8,
          child: Stack(
            children: [
              Container(
                width: _kAvatarSize,
                height: _kAvatarSize,
                margin: const EdgeInsets.only(right: 8, bottom: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceDim,
                  border: Border.all(
                    color: colors.accentWarm.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accentWarm.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: hasImage
                      ? Image.file(
                          File(resolvedPath),
                          width: _kAvatarSize,
                          height: _kAvatarSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => RevericIcon(
                            RevericIcons.person,
                            size: 48,
                            color: colors.textMuted,
                          ),
                        )
                      : RevericIcon(
                          RevericIcons.person,
                          size: 48,
                          color: colors.textMuted.withValues(alpha: 0.6),
                        ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: Center(
                    child: RevericIcon(
                      RevericIcons.add,
                      size: 14,
                      color: colors.onAccent,
                    ),
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

class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.onChanged,
    required this.length,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final int length;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return TextField(
      controller: controller,
      maxLength: _kUsernameMaxLength,
      style: typo.uiSmall.copyWith(color: colors.textPrimary),
      buildCounter:
          (
            _, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) {
            return null;
          },
      decoration: InputDecoration(
        hintText: context.t(LocaleKeys.onboardingUsernameHint),
        hintStyle: typo.uiSmall.copyWith(color: colors.textMuted),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: RevericSpacing.md),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Text(
              '$length / $_kUsernameMaxLength',
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: colors.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          borderSide: BorderSide(color: colors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          borderSide: BorderSide(color: colors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          borderSide: BorderSide(color: colors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.md,
        ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final alpha = enabled ? 1.0 : 0.45;

    return SizedBox(
      height: _kPrimaryButtonHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.accentWarm.withValues(alpha: alpha),
              colors.accentAmber.withValues(alpha: alpha),
            ],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: colors.accentWarm.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: typo.uiSemibold.copyWith(
                      color: colors.onAccent,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  RevericIcon(
                    RevericIcons.arrow_forward,
                    size: 20,
                    color: colors.onAccent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final titleStyle = typo.display.copyWith(
      fontSize: 40,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: colors.textPrimary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${context.t(LocaleKeys.onboardingBrandWelcome)} ',
              ),
              TextSpan(
                text: 'Reveric',
                style: titleStyle.copyWith(color: colors.accentWarm),
              ),
            ],
          ),
          style: titleStyle,
        ),
        const SizedBox(height: RevericSpacing.lg),
        Text(
          context.t(LocaleKeys.onboardingBrandTagline),
          style: typo.body.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        const Wrap(
          spacing: RevericSpacing.x3l,
          runSpacing: RevericSpacing.md,
          children: [
            _FeaturePill(
              icon: RevericIcons.edit_outlined,
              titleKey: LocaleKeys.onboardingFeatureFocusTitle,
              subtitleKey: LocaleKeys.onboardingFeatureFocusSubtitle,
            ),
            _FeaturePill(
              icon: RevericIcons.auto_awesome,
              titleKey: LocaleKeys.onboardingFeatureInspirationTitle,
              subtitleKey: LocaleKeys.onboardingFeatureInspirationSubtitle,
            ),
            _FeaturePill(
              icon: RevericIcons.menu_book_outlined,
              titleKey: LocaleKeys.onboardingFeatureKnowledgeTitle,
              subtitleKey: LocaleKeys.onboardingFeatureKnowledgeSubtitle,
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
  });

  final String icon;
  final String titleKey;
  final String subtitleKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface.withValues(alpha: 0.92),
            border: Border.all(
              color: colors.accentWarm.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Center(
            child: RevericIcon(icon, size: 18, color: colors.accentWarm),
          ),
        ),
        const SizedBox(width: RevericSpacing.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(titleKey),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              context.t(subtitleKey),
              style: typo.uiSmall.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
