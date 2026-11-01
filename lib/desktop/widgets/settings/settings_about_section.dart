// 职责: 桌面端设置对话框关于入口 — 委托给共享 AboutSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/about_settings_section.dart
part of 'settings_dialog.dart';

class _AboutSettingsSection extends StatelessWidget {
  const _AboutSettingsSection();

  @override
  Widget build(BuildContext context) => const AboutSettingsSection();
}
