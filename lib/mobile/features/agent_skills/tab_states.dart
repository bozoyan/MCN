// 职责: 移动端技能 tab(官方 / 广场 / 我的)共用的空 / 错误占位构件,
//   消除 official_tab、marketplace_tab、mine_tab 的重复实现。
// 关联文件:
//   lib/mobile/features/agent_skills/official_tab.dart
//   lib/mobile/features/agent_skills/marketplace_tab.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';

/// Tab 内空状态:图标 + 单行文案。
class SkillTabEmptyState extends StatelessWidget {
  const SkillTabEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final String icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RevericPlaceholder.empty(icon: icon, title: message),
    );
  }
}

/// Tab 内错误态 + 重试按钮。
class SkillTabErrorRetry extends StatelessWidget {
  const SkillTabErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RevericPlaceholder.error(
        title: message,
        action: RevericButton.secondary(
          label: context.t(LocaleKeys.agentSkillRetry),
          onPressed: onRetry,
        ),
      ),
    );
  }
}
