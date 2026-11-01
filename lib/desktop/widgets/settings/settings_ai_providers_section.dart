// 职责: 桌面端设置对话框 AI providers 入口 — 委托给共享 AiProvidersSection（内部按宽度自适应两栏 / 列表）。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/ai_providers_section.dart
//   lib/shared/widgets/settings/provider_config_panel.dart
part of 'settings_dialog.dart';

class _AiProvidersSection extends StatelessWidget {
  const _AiProvidersSection();

  @override
  Widget build(BuildContext context) => AiProvidersSection();
}
