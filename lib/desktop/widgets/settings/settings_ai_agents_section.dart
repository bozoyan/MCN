// 职责: 桌面端设置对话框 AI 助手设置入口 — 委托给共享 AiAgentsSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/ai_agents_settings_section.dart
part of 'settings_dialog.dart';

class _AiAgentSettingsSection extends StatelessWidget {
  const _AiAgentSettingsSection();

  @override
  Widget build(BuildContext context) => const AiAgentsSettingsSection();
}
