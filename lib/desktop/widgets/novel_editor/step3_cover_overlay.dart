// 职责: 小说编辑页新手引导第 3 步 — 在封面缩略图旁浮出封面工作室引导气泡。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/ai/chat/chat_onboarding_bubble.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../ai/chat/chat_onboarding_bubble.dart';

class NovelEditorStep3CoverOverlay extends HookWidget {
  const NovelEditorStep3CoverOverlay({
    super.key,
    required this.onboardingStep,
    required this.thumbnailKey,
    required this.onDismiss,
  });

  final int onboardingStep;
  final GlobalKey thumbnailKey;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final active = onboardingStep == 3;
    final overlayController = useMemoized(
      () => OverlayPortalController(debugLabel: 'step3_cover'),
      [],
    );

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        if (active) {
          overlayController.show();
        } else {
          overlayController.hide();
        }
      });
      return null;
    }, [active]);

    return OverlayPortal(
      controller: overlayController,
      overlayChildBuilder: (context) {
        if (!active) {
          return const SizedBox.shrink();
        }
        final renderBox =
            thumbnailKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          return const SizedBox.shrink();
        }
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        const bubbleWidth = 320.0;

        return Positioned(
          left: position.dx + size.width + RevericSpacing.lg,
          top: position.dy + size.height / 2 - 90,
          child: ChatOnboardingBubble(
            stepIndex: 3,
            totalSteps: 3,
            title: context.t(LocaleKeys.aiChatOnboardingCoverTitle),
            message: context.t(LocaleKeys.aiChatOnboardingCoverMessage),
            tail: OnboardingBubbleTail.rightCenter,
            width: bubbleWidth,
            onDismiss: onDismiss,
            onNext: null,
          ),
        );
      },
      child: const SizedBox.shrink(),
    );
  }
}
