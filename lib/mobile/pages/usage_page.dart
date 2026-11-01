// 职责: 移动端用量页面 — 承载共享 UsageView，并支持直接下钻当前 AI 会话。
// 关联文件:
//   lib/shared/widgets/settings/usage_view.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/settings/usage_view.dart';

class MobileUsagePage extends StatelessWidget {
  const MobileUsagePage({super.key, this.initialSessionId});

  final String? initialSessionId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: RevericIcon(
            RevericIcons.chevron_left,
            size: 24,
            color: colors.textSecondary,
          ),
        ),
        title: Text(
          context.t(LocaleKeys.settingsUsage),
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
      ),
      body: UsageView(showHeader: false, initialSessionId: initialSessionId),
    );
  }
}
