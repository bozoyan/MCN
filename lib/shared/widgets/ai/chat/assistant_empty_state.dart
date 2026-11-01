// 职责: AI 聊天面板空会话欢迎态 — 展示插画、欢迎语与固定目录引导卡片，双端共用。
// 关联文件:
//   lib/shared/heuristic/chat_next_action.dart
//   lib/shared/widgets/ai/chat/next_action_bar.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/heuristic.json
//   assets/translations/zh-CN/heuristic.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/reveric_surfaces.dart';
import '../../../heuristic/chat_next_action.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';
import 'next_action_bar.dart';

/// AI 写作助手空会话欢迎态。
///
/// 空会话时一次模型调用都还没发生，建议只能来自客户端固定目录（[emptyStateActions]）。
/// 这是整个下一步建议方案里唯一保留的本地逻辑。
class AssistantEmptyState extends StatelessWidget {
  const AssistantEmptyState({
    super.key,
    required this.actions,
    required this.onActionTap,
    this.illustrationHeight = 180,
  });

  final List<ChatNextAction> actions;
  final ValueChanged<ChatNextAction> onActionTap;
  final double illustrationHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x4l,
        RevericSpacing.x3l,
        RevericSpacing.x4l,
        RevericSpacing.x4l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SvgPicture.asset(
              'assets/illustrations/ai_assistant_window.svg',
              height: illustrationHeight,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          Text(
            context.t(LocaleKeys.aiAssistantWelcomeTitle),
            textAlign: TextAlign.center,
            style: typo.uiSemibold.copyWith(
              color: colors.textPrimary,
              height: 1.55,
              fontSize: 16,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.x5l),
            Padding(
              padding: const EdgeInsets.only(left: RevericSpacing.xs),
              child: Text(
                context.t(LocaleKeys.aiAssistantQuickstartTitle),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: RevericSpacing.md),
              _AssistantQuickActionTile(
                action: actions[i],
                onTap: () => onActionTap(actions[i]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AssistantQuickActionTile extends StatelessWidget {
  const _AssistantQuickActionTile({required this.action, required this.onTap});

  final ChatNextAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final subtitleKey = action.subtitleKey;

    return RevericElevatedInkWell(
      fallback: colors.surface,
      onTap: onTap,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Row(
        children: [
          RevericElevatedCard(
            fallback: colors.surfaceContainerHigh,
            width: 34,
            height: 34,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
            alignment: Alignment.center,
            child: RevericIcon(
              nextActionIconAsset(action),
              size: 18,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolveNextActionLabel(context, action),
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                if (subtitleKey != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.t(subtitleKey),
                    style: typo.uiSmall.copyWith(
                      color: colors.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          RevericIcon(
            RevericIcons.arrow_forward_rounded,
            size: 16,
            color: colors.textSubtle,
          ),
        ],
      ),
    );
  }
}

/// 空态目录项的文案来自 locale key；模型产出的建议直接用运行时 label（不参与 i18n）。
String resolveNextActionLabel(BuildContext context, ChatNextAction action) {
  final labelKey = action.labelKey;
  return labelKey == null ? action.label : context.t(labelKey);
}

/// 提示词类建议要填进 composer 的文本。
///
/// 空态目录项的 prompt 存的是 locale key（见 [emptyStateActions]），模型产出的
/// 建议存的是运行时原文；靠 [ChatNextAction.labelKey] 区分，不猜内容。
String resolveNextActionPrompt(BuildContext context, ChatNextAction action) {
  final target = action.target;
  if (target is! PromptActionTarget) {
    return '';
  }
  return action.labelKey == null ? target.prompt : context.t(target.prompt);
}
