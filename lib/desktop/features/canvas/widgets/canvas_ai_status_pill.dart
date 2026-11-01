// 职责: 画布顶部 AI 状态条 — 显示 AI 当前在画布上做什么,并提供跟随开关
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/shared/models/canvas_ai_activity.dart
//   lib/shared/widgets/app_background.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/canvas_ai_activity.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/widgets/app_background.dart';

/// 画布顶部居中的 AI 状态条。
///
/// 画布上「谁在改、改的是什么」原本完全不可见:AI 写库后节点可能落在视野外,
/// 用户只看到一张纹丝不动的画布。这条 pill 把当前工具翻译成一句人话,并在
/// 跟随被用户接管时给出恢复入口。
///
/// [visible] 为 false 时淡出但保持挂载(避免每次活动切换都重建动画)。
class CanvasAiStatusPill extends HookConsumerWidget {
  const CanvasAiStatusPill({
    super.key,
    required this.visible,
    required this.kind,
    required this.following,
    required this.onToggleFollow,
    this.multi = false,
  });

  /// 是否显示。活动停止一段时间后由导演置 false。
  final bool visible;

  /// 本轮唯一的活动类型;null 时只显示通用文案。
  final CanvasAiActivityKind? kind;

  /// 本轮出现了多种写操作(模型常并发 add_node + add_edge)。
  ///
  /// 逐条翻文案会在几帧内闪好几次,这里统一说一句「正在编辑画布」。
  final bool multi;

  /// 镜头是否仍在跟随 AI。用户一动手就为 false。
  final bool following;

  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    // 呼吸点:表示「还在进行中」。停用时不跑动画,省掉常驻重绘。
    final pulse = useAnimationController(
      duration: const Duration(milliseconds: 1100),
    );
    useEffect(() {
      if (visible) {
        pulse.repeat(reverse: true);
      } else {
        pulse.stop();
      }
      return null;
    }, [visible, pulse]);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: appElevatedBackgroundColor(
              colors,
              appBackgroundActive,
              colors.surface,
            ),
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.textPrimary.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(animation: pulse, color: colors.accent),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                multi
                    ? context.t(LocaleKeys.canvasAiStatusEditing)
                    : _statusLabel(context, kind),
                style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: RevericSpacing.sm),
              _FollowToggle(
                following: following,
                onTap: onToggleFollow,
                colors: colors,
                typo: typo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工具类型 → 一句人话。
String _statusLabel(BuildContext context, CanvasAiActivityKind? kind) {
  return switch (kind) {
    CanvasAiActivityKind.scan => context.t(LocaleKeys.canvasAiStatusScanning),
    CanvasAiActivityKind.add_node => context.t(
      LocaleKeys.canvasAiStatusAddingNode,
    ),
    CanvasAiActivityKind.update_node => context.t(
      LocaleKeys.canvasAiStatusUpdatingNode,
    ),
    CanvasAiActivityKind.remove_node => context.t(
      LocaleKeys.canvasAiStatusRemovingNode,
    ),
    CanvasAiActivityKind.add_edge => context.t(
      LocaleKeys.canvasAiStatusAddingEdge,
    ),
    CanvasAiActivityKind.remove_edge => context.t(
      LocaleKeys.canvasAiStatusRemovingEdge,
    ),
    CanvasAiActivityKind.auto_layout => context.t(
      LocaleKeys.canvasAiStatusArranging,
    ),
    CanvasAiActivityKind.create_canvas => context.t(
      LocaleKeys.canvasAiStatusCreatingCanvas,
    ),
    CanvasAiActivityKind.open_canvas => context.t(
      LocaleKeys.canvasAiStatusOpeningCanvas,
    ),
    null => context.t(LocaleKeys.canvasAiStatusScanning),
  };
}

/// 呼吸点。
class _PulseDot extends AnimatedWidget {
  const _PulseDot({required Animation<double> animation, required this.color})
    : super(listenable: animation);

  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = (listenable as Animation<double>).value;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.45 + 0.55 * value),
      ),
    );
  }
}

/// 跟随开关。暂停时同时说明「为什么镜头不动了」,否则用户只会以为功能坏了。
class _FollowToggle extends StatelessWidget {
  const _FollowToggle({
    required this.following,
    required this.onTap,
    required this.colors,
    required this.typo,
  });

  final bool following;
  final VoidCallback onTap;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    final label = following
        ? context.t(LocaleKeys.canvasFollowAi)
        : '${context.t(LocaleKeys.canvasFollowPaused)} · '
              '${context.t(LocaleKeys.canvasFollowResume)}';
    final fg = following ? colors.accent : colors.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.xs,
            vertical: 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                following
                    ? RevericIcons.visibility
                    : RevericIcons.visibility_off,
                size: 14,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(label, style: typo.uiTinySemibold.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
