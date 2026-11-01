// 职责: 新会话里的延续提议条 — 展示「延续上一个对话为新对话」，5 秒后自动隐藏（悬停保持）
// 关联文件:
//   lib/shared/providers/chat_continue_offer_provider.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../providers/chat_continue_offer_provider.dart';
import '../../../theme/theme.dart';

/// 提议条自动隐藏的等待时间。鼠标移入时取消，移出后重新计时。
const _autoHideDelay = Duration(seconds: 5);

/// 进场动效时长。只活 5 秒，静态出现容易被完全忽略。
const _enterDuration = Duration(milliseconds: 180);

/// 点「新对话」后在新会话的输入框正上方提议一次「延续刚才那个对话」。
///
/// 只提议这一次：超时、关闭或接受之后都不再回来，想延续任意会话仍走会话列表的
/// 延续入口。没有待提议内容时整条不渲染，不占高度、不留占位。
class ContinueSessionOfferBar extends HookConsumerWidget {
  const ContinueSessionOfferBar({
    super.key,
    required this.novelId,
    required this.onAccept,
  });

  final String novelId;

  /// 参数是来源会话 id。
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(chatContinueOfferProvider);
    final notifier = ref.read(chatContinueOfferProvider.notifier);
    // 提议可能是在别的作品里挂上的（桌面端切作品不重建面板），只认本作品的。
    final visible = offer != null && offer.novelId == novelId;

    final hideTimer = useRef<Timer?>(null);
    void cancelHide() {
      hideTimer.value?.cancel();
      hideTimer.value = null;
    }

    void scheduleHide() {
      cancelHide();
      hideTimer.value = Timer(_autoHideDelay, notifier.clear);
    }

    useEffect(() {
      if (!visible) {
        return null;
      }
      scheduleHide();
      return cancelHide;
    }, [visible, offer?.sourceSessionId]);

    // 验收硬要求：在最外层就返回，外面不能再包 Padding，否则会留下莫名空白。
    if (!visible) {
      return const SizedBox.shrink();
    }

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = context.t(
      LocaleKeys.aiChatContinueOffer,
      namedArgs: {'title': offer.title},
    );

    // 宽度撑满并左对齐：本条常被放进默认 CrossAxisAlignment.center 的 Column
    // （desktop panel 的根 Column 就是），只按内容宽度会被父级居中。
    // 底色和描边走 accent：中性灰的 pill 会和空态目录卡糊在一起，而这条只活
    // 5 秒，看不见就等于没有。
    final tint = colors.accent;
    return SizedBox(
      width: double.infinity,
      child: MouseRegion(
        onEnter: (_) => cancelHide(),
        onExit: (_) => scheduleHide(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.lg,
            0,
            RevericSpacing.lg,
            RevericSpacing.sm,
          ),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(offer.sourceSessionId),
            tween: Tween(begin: 0, end: 1),
            duration: _enterDuration,
            curve: Curves.easeOut,
            builder: (context, progress, child) => Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, (1 - progress) * 6),
                child: child,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () {
                        notifier.clear();
                        onAccept(offer.sourceSessionId);
                      },
                      borderRadius: BorderRadius.circular(RevericRadius.pill),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                          RevericSpacing.md,
                          5,
                          RevericSpacing.xs,
                          5,
                        ),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            RevericRadius.pill,
                          ),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RevericIcon(
                              RevericIcons.git_fork,
                              size: 13,
                              color: tint,
                            ),
                            const SizedBox(width: RevericSpacing.xs),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: typo.uiMedium.copyWith(color: tint),
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.xxs),
                            // 关闭嵌在 pill 里：飘在外面的裸 ✕ 看起来不像同一
                            // 个控件的一部分。内层 InkWell 吃掉点击，不会误触
                            // 外层的「接受」。
                            InkWell(
                              onTap: notifier.clear,
                              borderRadius: BorderRadius.circular(
                                RevericRadius.pill,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  RevericSpacing.xxs,
                                ),
                                child: RevericIcon(
                                  RevericIcons.close,
                                  size: 11,
                                  color: tint.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
