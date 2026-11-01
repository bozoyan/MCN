// 职责: 移动端首次启动引导页 — 填写 AI 称呼与头像，后台应用默认配置并创建 Demo 小说。
// 关联文件:
//   lib/shared/hooks/use_onboarding_setup.dart
//   lib/shared/utils/avatar_storage.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/onboarding.json
//   assets/translations/zh-CN/onboarding.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/hooks/use_onboarding_setup.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/theme/theme.dart';
import '../../shared/utils/avatar_storage.dart';
import '../../shared/utils/storage_paths.dart';
import '../app.dart';

final _log = AppLogger.forModule('MobileOnboarding');

const int _kUsernameMaxLength = 20;
const double _kAvatarSize = 88;

class MobileOnboardingPage extends HookConsumerWidget {
  const MobileOnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final setup = useOnboardingSetup(ref);
    final usernameController = setup.nameController;
    final avatarPath = setup.avatarPath;
    useListenable(usernameController);
    useListenable(avatarPath);
    final isPickingAvatar = useState(false);
    final isSubmitting = useState(false);

    Future<void> pickAvatar() async {
      if (!setup.defaultsReady || isPickingAvatar.value) {
        return;
      }
      isPickingAvatar.value = true;
      try {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (!context.mounted || picked == null) {
          return;
        }
        final stored = await storeAvatarFile(picked.path);
        if (!context.mounted) {
          return;
        }
        avatarPath.value = stored;
        await setup.saveProfile();
      } catch (error, stackTrace) {
        _log.error(
          'Mobile onboarding avatar selection failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      } finally {
        if (context.mounted) {
          isPickingAvatar.value = false;
        }
      }
    }

    final trimmedName = usernameController.text.trim();
    final canSubmit = trimmedName.isNotEmpty && !isSubmitting.value;

    Future<void> completeOnboarding() async {
      if (!canSubmit) {
        return;
      }
      isSubmitting.value = true;
      try {
        await setup.complete();
        if (context.mounted) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MobileApp()),
          );
        }
      } catch (error, stackTrace) {
        _log.error(
          'Mobile onboarding complete failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          isSubmitting.value = false;
        }
      }
    }

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x4l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${context.t(LocaleKeys.onboardingBrandWelcome)} ',
                    ),
                    TextSpan(
                      text: 'Reveric',
                      style: typo.display.copyWith(
                        color: colors.accentWarm,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: RevericSpacing.lg),
              Text(
                context.t(LocaleKeys.onboardingBrandTagline),
                style: typo.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.onboardingProfileCardSubtitle),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.x5l),
              Center(
                child: _MobileAvatarPicker(
                  key: const ValueKey('onboarding-avatar-picker'),
                  path: avatarPath.value,
                  isLoading: isPickingAvatar.value,
                  onTap: pickAvatar,
                ),
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
              TextField(
                controller: usernameController,
                maxLength: _kUsernameMaxLength,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => unawaited(setup.saveProfile()),
                onSubmitted: (_) => completeOnboarding(),
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
                        '${usernameController.text.length} / $_kUsernameMaxLength',
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
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
              ),
              const SizedBox(height: RevericSpacing.x4l),
              SizedBox(
                height: RevericSizes.buttonHeight + 8,
                child: FilledButton(
                  onPressed: canSubmit ? completeOnboarding : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    disabledBackgroundColor: colors.accent.withValues(
                      alpha: 0.45,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        RevericRadius.button,
                      ),
                    ),
                  ),
                  child: isSubmitting.value
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onAccent,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t(LocaleKeys.onboardingGetStarted),
                              style: typo.uiSemibold.copyWith(
                                color: colors.onAccent,
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.sm),
                            RevericIcon(
                              RevericIcons.arrow_forward,
                              size: 18,
                              color: colors.onAccent,
                            ),
                          ],
                        ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileAvatarPicker extends StatelessWidget {
  const _MobileAvatarPicker({
    super.key,
    required this.path,
    required this.isLoading,
    required this.onTap,
  });

  final String? path;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    // 存储值可能是相对/旧绝对路径；预览统一过 resolveStored 兜底。
    final resolvedPath = RevericPaths.resolveStored(path);
    final hasImage = resolvedPath != null;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
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
                        cacheWidth: (_kAvatarSize * 2).toInt(),
                        errorBuilder: (_, _, _) => RevericIcon(
                          RevericIcons.person,
                          size: 44,
                          color: colors.textMuted,
                        ),
                      )
                    : RevericIcon(
                        RevericIcons.person,
                        size: 44,
                        color: colors.textMuted.withValues(alpha: 0.6),
                      ),
              ),
            ),
            if (isLoading)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceDim.withValues(alpha: 0.72),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
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
    );
  }
}
