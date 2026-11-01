// 职责: 桌面端设置对话框外观设置入口 — 委托给共享 AppearanceSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/appearance_settings_section.dart
part of 'settings_dialog.dart';

class _AppearanceSettingsSection extends StatelessWidget {
  const _AppearanceSettingsSection();

  @override
  Widget build(BuildContext context) => const AppearanceSettingsSection();
}
