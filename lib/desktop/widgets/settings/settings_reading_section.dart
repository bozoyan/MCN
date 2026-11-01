// 职责: 桌面端设置对话框阅读设置入口 — 委托给共享 ReadingSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/reading_settings_section.dart
part of 'settings_dialog.dart';

class _ReadingSettingsSection extends StatelessWidget {
  const _ReadingSettingsSection();

  @override
  Widget build(BuildContext context) =>
      const ReadingSettingsSection(platform: ReadingSettingsPlatform.desktop);
}
