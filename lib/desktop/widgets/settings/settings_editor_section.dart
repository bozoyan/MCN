// 职责: 桌面端设置对话框编辑器设置入口 — 委托给共享 EditorSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/editor_settings_section.dart
part of 'settings_dialog.dart';

class _EditorSettingsSection extends StatelessWidget {
  const _EditorSettingsSection();

  @override
  Widget build(BuildContext context) =>
      const EditorSettingsSection(showMinimapSetting: true);
}
