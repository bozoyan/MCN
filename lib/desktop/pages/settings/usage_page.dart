// 职责: 桌面端用量统计页面 — 套上桌面 Scaffold 与全局背景，委托共享 UsageView 渲染内容。
// 关联文件:
//   lib/shared/widgets/settings/usage_view.dart
//   lib/shared/widgets/app_background.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../shared/widgets/settings/usage_view.dart';

/// Usage 统计页面（桌面端）
class UsagePage extends ConsumerWidget {
  const UsagePage({super.key, this.initialSessionId});

  final String? initialSessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    return Scaffold(
      backgroundColor: appScaffoldBackgroundColor(colors, appBackgroundActive),
      body: UsageView(initialSessionId: initialSessionId),
    );
  }
}
