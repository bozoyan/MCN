// 职责: 移动端作品内 AI 页统一 AppBar — 头像（点击打开助手权限）、标题/副标题、历史/新建、模式切换条与底部分隔线。
// 关联文件:
//   lib/mobile/widgets/mobile_ai_mode.dart
//   lib/mobile/widgets/mobile_ai_mode_switch_strip.dart
//   lib/shared/models/ai_session_mode.dart
//   lib/shared/widgets/ai/ai_avatar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';

import '../../shared/localization/locale_keys.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/components/reveric_icon_button.dart';
import '../../shared/models/ai_session_mode.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/ai/ai_avatar.dart';
import 'mobile_ai_mode.dart';
import 'mobile_ai_mode_switch_strip.dart';

/// 模式切换条 + 底部分隔线的 preferred height。
const double kMobileAiSessionAppBarBottomHeight = 43;

/// 构建作品内 AI 五模式页共用的 [AppBar]（含横向模式切换条）。
AppBar buildMobileAiSessionAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  required AiSessionMode currentMode,
  required MobileAiNovelContext novelContext,
  String? currentSessionId,
  VoidCallback? onHistory,
  VoidCallback? onNew,
  String? historyTooltip,
  String? newSessionTooltip,
  bool showHistory = true,
  bool showNew = true,
  ValueChanged<AiSessionMode>? onModeSelected,
  VoidCallback? onPermissions,
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  return AppBar(
    backgroundColor: colors.canvas,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: RevericIconButton(
      icon: RevericIcons.chevron_left,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    titleSpacing: 0,
    title: Row(
      children: [
        // 头像外扩到 48px 触控区，同时充当与返回键、标题之间的间距。
        AiAvatar(
          size: RevericSizes.aiAvatarMd,
          icon: _avatarIcon(currentMode),
          tooltip: context.t(LocaleKeys.aiPermissionsTitle),
          onTap: onPermissions,
          hitPadding: const EdgeInsets.all(RevericSpacing.lg),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
      ],
    ),
    actionsPadding: const EdgeInsets.only(right: RevericSpacing.lg),
    actions: [
      if (showHistory && onHistory != null)
        RevericIconButton(
          tooltip: historyTooltip ?? context.t(LocaleKeys.aiChatHistory),
          icon: RevericIcons.history_rounded,
          onPressed: onHistory,
        ),
      // 直接新建，不再先弹「新对话 / 延续」二选一：延续降级成新会话里的一次性
      // 提议条（ContinueSessionOfferBar）。
      if (showNew && onNew != null)
        RevericIconButton(
          tooltip: newSessionTooltip ?? context.t(LocaleKeys.aiNewSession),
          icon: RevericIcons.add,
          onPressed: onNew,
        ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(kMobileAiSessionAppBarBottomHeight),
      child: Column(
        children: [
          MobileAiModeSwitchStrip(
            currentMode: currentMode,
            novelContext: novelContext,
            currentSessionId: currentSessionId,
            onModeSelected: onModeSelected,
          ),
          Divider(height: 1, thickness: 1, color: colors.borderSubtle),
        ],
      ),
    ),
  );
}

/// 与桌面端各模式标题栏头像图标保持一致。
String _avatarIcon(AiSessionMode mode) => switch (mode) {
  AiSessionMode.council => RevericIcons.groups_outlined,
  AiSessionMode.monologue => RevericIcons.psychology_rounded,
  AiSessionMode.theater => RevericIcons.theater_comedy_rounded,
  AiSessionMode.roleplay => RevericIcons.mask_happy_rounded,
  AiSessionMode.chat => RevericIcons.auto_awesome,
};

/// 作品内 AI 页 [Scaffold] 外壳：canvas 背景 + 统一 AppBar + body。
class MobileAiSessionScaffold extends StatelessWidget {
  const MobileAiSessionScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.currentMode,
    required this.novelContext,
    required this.body,
    this.currentSessionId,
    this.onHistory,
    this.onNew,
    this.historyTooltip,
    this.newSessionTooltip,
    this.showHistory = true,
    this.showNew = true,
    this.onModeSelected,
    this.onPermissions,
  });

  final String title;
  final String? subtitle;
  final AiSessionMode currentMode;
  final MobileAiNovelContext novelContext;
  final Widget body;

  /// 当前页会话 id，供模式条切走时写入进程内记忆。
  final String? currentSessionId;
  final VoidCallback? onHistory;
  final VoidCallback? onNew;
  final String? historyTooltip;
  final String? newSessionTooltip;
  final bool showHistory;
  final bool showNew;
  final ValueChanged<AiSessionMode>? onModeSelected;

  /// 点击头像打开「助手权限」；为空时头像不可点击。
  final VoidCallback? onPermissions;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      resizeToAvoidBottomInset: true,
      appBar: buildMobileAiSessionAppBar(
        context,
        title: title,
        subtitle: subtitle,
        currentMode: currentMode,
        novelContext: novelContext,
        currentSessionId: currentSessionId,
        onHistory: onHistory,
        onNew: onNew,
        historyTooltip: historyTooltip,
        newSessionTooltip: newSessionTooltip,
        showHistory: showHistory,
        showNew: showNew,
        onModeSelected: onModeSelected,
        onPermissions: onPermissions,
      ),
      body: body,
    );
  }
}
