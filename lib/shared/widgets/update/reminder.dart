// 职责: 展示自动更新轻提示及调试页发起的验证，管理关闭与超时。
// 关联文件:
//   lib/shared/providers/update_providers.dart
//   lib/main.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app_config.dart' show appVersion;
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/update_providers.dart';
import '../../theme/theme.dart';

class UpdateReminder extends HookConsumerWidget {
  const UpdateReminder({
    super.key,
    required this.onViewUpdate,
    required this.mobile,
  });

  final VoidCallback onViewUpdate;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(availableUpdateProvider);
    final previewRequest = ref.watch(updateReminderPreviewProvider);
    final handledPreview = useRef(previewRequest);
    final lifecycle = useAppLifecycleState();
    final visibleVersion = useState<String?>(null);
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;

    useOnAppLifecycleStateChange((previous, next) {
      if (next == AppLifecycleState.resumed) {
        unawaited(ref.read(latestReleaseProvider.notifier).refresh());
      }
    });

    useEffect(() {
      var active = true;
      Timer? timer;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!active || !context.mounted) {
          return;
        }
        visibleVersion.value = null;
        final preview = previewRequest != handledPreview.value;
        handledPreview.value = previewRequest;
        final version = info?.version ?? (preview ? appVersion : null);
        if (!foreground || version == null) {
          return;
        }
        final notifier = ref.read(latestReleaseProvider.notifier);
        final notify = preview || await notifier.shouldNotify(version);
        if (!active || !context.mounted || !notify) {
          return;
        }
        visibleVersion.value = version;
        if (!preview) {
          unawaited(notifier.markNotified(version));
        }
        // 辅助功能用户可自行关闭，不强制限时阅读与操作。
        if (!WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .accessibleNavigation) {
          timer = Timer(const Duration(seconds: 8), () {
            if (active && context.mounted) {
              visibleVersion.value = null;
            }
          });
        }
      });
      return () {
        active = false;
        timer?.cancel();
      };
    }, [info?.version, foreground, previewRequest]);

    final version = visibleVersion.value;
    if (version == null || !foreground) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // 移动端按触控目标放大关闭热区，桌面端沿用统一 IconButton 尺寸。
    final closeSize = mobile
        ? RevericSizes.buttonHeight
        : RevericSizes.iconButtonSize;
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: RevericSpacing.x2l,
            right: RevericSpacing.x2l,
            top: RevericSpacing.x2l,
            // 移动端避开根 Tab 栏，也不覆盖软键盘。
            bottom: mobile
                ? bottomInset + RevericSpacing.x6l * 2
                : RevericSpacing.x2l,
          ),
          child: Align(
            alignment: mobile ? Alignment.bottomCenter : Alignment.bottomLeft,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(version),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * RevericSpacing.lg),
                  child: child,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(RevericRadius.x2l),
                    border: Border.all(color: colors.border),
                    boxShadow: [
                      BoxShadow(
                        color: colors.textPrimary.withValues(alpha: 0.16),
                        blurRadius: 40,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RevericSpacing.lg,
                        RevericSpacing.md,
                        RevericSpacing.sm,
                        RevericSpacing.md,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: RevericSizes.iconButtonSize,
                              height: RevericSizes.iconButtonSize,
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  RevericRadius.large,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: RevericIcon(
                                RevericIcons.system_update_outlined,
                                size: RevericSizes.aiAvatarSm,
                                color: colors.accent,
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.lg),
                            Flexible(
                              child: Text(
                                context.t(
                                  LocaleKeys.settingsUpdateReleased,
                                  namedArgs: {'version': version},
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: typo.uiMedium.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.sm),
                            TextButton(
                              onPressed: () {
                                visibleVersion.value = null;
                                onViewUpdate();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: colors.accent,
                                textStyle: typo.uiSmallSemibold,
                                minimumSize: Size(0, closeSize),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: RevericSizes.buttonPaddingHSm,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                context.t(LocaleKeys.settingsUpdateView),
                              ),
                            ),
                            // 提示位于 Navigator 外层，不依赖路由的 Tooltip Overlay。
                            Semantics(
                              label: context.t(LocaleKeys.commonClose),
                              child: SizedBox(
                                width: closeSize,
                                height: closeSize,
                                child: IconButton(
                                  onPressed: () => visibleVersion.value = null,
                                  padding: EdgeInsets.zero,
                                  iconSize: RevericSpacing.x2l,
                                  icon: RevericIcon(
                                    RevericIcons.close,
                                    size: RevericSpacing.x2l,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
