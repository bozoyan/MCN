// 职责: 共享用量统计设置区 — 承载平台特定的用量统计 body。
// 关联文件:
//   lib/desktop/pages/settings/usage_page.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/directory-structure.md

import 'package:flutter/material.dart';

/// 渲染用量统计 body 的构建器。桌面端注入 UsagePage，移动端注入 UsageView。
typedef UsageBodyBuilder = Widget Function();

/// 用量统计 section：委托给平台特定的 body 构建器。
class UsageSettingsSection extends StatelessWidget {
  const UsageSettingsSection({super.key, required this.bodyBuilder});

  final UsageBodyBuilder bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return bodyBuilder();
  }
}
