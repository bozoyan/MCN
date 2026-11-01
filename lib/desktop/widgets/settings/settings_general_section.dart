// 职责: 桌面端设置对话框通用设置入口 — 委托给共享 GeneralSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/general_settings_section.dart
part of 'settings_dialog.dart';

class _GeneralSettingsSection extends StatelessWidget {
  const _GeneralSettingsSection();

  @override
  Widget build(BuildContext context) => const GeneralSettingsSection();
}
