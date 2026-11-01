// 职责: AI 模式的单条 Agent 消息外壳 — 头像、名字、附加信息、详情入口、右侧操作与气泡；生成中与生成后是同一张卡片，内容由各模式提供。
// 关联文件:
//   lib/shared/widgets/ai/typing_dots.dart
//   lib/shared/widgets/ai/thinking_card.dart
//   lib/shared/widgets/ai/theater_line_body.dart
//   lib/shared/widgets/ai/monologue_body.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'thinking_card.dart';
import 'typing_dots.dart';

/// 桌面面板偏紧凑；移动端字号、头像与留白更大，气泡撑满宽度。
enum AgentMessageDensity { panel, mobile }

class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.accentColor,
    required this.density,
    this.meta,
    this.subtitle,
    this.thinking = '',
    this.streaming = false,
    this.onOpenDetail,
    this.trailing,
    this.body,
  });

  /// 调用方按 [avatarSize] 构建头像。
  final Widget avatar;
  final String name;
  final Color accentColor;
  final AgentMessageDensity density;

  /// 名字后的弱化信息，如「第 2 轮」。
  final String? meta;

  /// 头部下方的一行说明，如议会成员的职责。
  final String? subtitle;
  final String thinking;

  /// 生成中：思考内容不可选，[body] 为 null 时显示跳动三点。
  final bool streaming;
  final VoidCallback? onOpenDetail;

  /// 头部最右侧的操作（如「…」菜单）。
  final Widget? trailing;
  final Widget? body;

  static double avatarSize(AgentMessageDensity density) =>
      density == AgentMessageDensity.mobile ? 36 : 32;

  /// 气泡正文的基准字体，各模式的内容组件以此派生。
  static TextStyle bodyStyle(
    BuildContext context,
    AgentMessageDensity density,
  ) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return density == AgentMessageDensity.mobile
        ? typo.bodySmall.copyWith(color: colors.textPrimary, height: 1.7)
        : typo.ui.copyWith(color: colors.textPrimary, height: 1.5);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mobile = density == AgentMessageDensity.mobile;
    final openDetail = onOpenDetail;
    final content = body;
    final meta = this.meta;
    final subtitle = this.subtitle?.trim();
    final trailing = this.trailing;

    // 左侧信息组吃掉剩余宽度，右侧操作贴边；名字过长时只截断名字。
    final header = Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: mobile
                      ? typo.uiSemibold.copyWith(color: accentColor)
                      : typo.uiSmall.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  meta,
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
              ],
              if (openDetail != null) ...[
                SizedBox(
                  width: mobile ? RevericSpacing.xs : RevericSpacing.sm,
                ),
                mobile
                    ? _MobileDetailButton(onTap: openDetail)
                    : _PanelDetailButton(onTap: openDetail),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );

    final bubble = Container(
      width: mobile ? double.infinity : null,
      padding: const EdgeInsets.all(RevericSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(
          mobile ? RevericRadius.x2l : RevericRadius.xl,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thinking.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                bottom: content == null && !streaming ? 0 : RevericSpacing.sm,
              ),
              child: ThinkingCard(content: thinking, selectable: !streaming),
            ),
          if (content != null)
            content
          else if (streaming)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
              child: TypingDots(color: accentColor),
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: mobile ? RevericSpacing.lg : RevericSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          SizedBox(width: mobile ? RevericSpacing.md : RevericSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                SizedBox(
                  height: mobile ? RevericSpacing.sm : RevericSpacing.xxs,
                ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelDetailButton extends StatelessWidget {
  const _PanelDetailButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Tooltip(
      message: context.t(LocaleKeys.aiExpandDetails),
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 24),
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
          side: BorderSide(color: colors.border.withValues(alpha: 0.7)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
          ),
        ),
        icon: RevericIcon(
          RevericIcons.open_in_full_rounded,
          size: 12,
          color: colors.textSubtle,
        ),
        label: Text(
          context.t(LocaleKeys.aiDetails),
          style: typo.uiTiny.copyWith(color: colors.textSubtle),
        ),
      ),
    );
  }
}

class _MobileDetailButton extends StatelessWidget {
  const _MobileDetailButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.xxs),
        child: RevericIcon(
          RevericIcons.open_in_full_rounded,
          size: 13,
          color: colors.textSubtle,
        ),
      ),
    );
  }
}
