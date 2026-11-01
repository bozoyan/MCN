// 职责: 桌面端设置对话框 — 承载独立的备份设置区。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/backup_settings_section.dart
// 遵循的 Rules:
//   .agents/rules/directory-structure.md
part of 'settings_dialog.dart';

class _BackupSettingsSection extends StatelessWidget {
  const _BackupSettingsSection();

  @override
  Widget build(BuildContext context) => const BackupSettingsSection();
}
