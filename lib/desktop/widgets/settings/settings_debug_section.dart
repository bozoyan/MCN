// 职责: 桌面端设置对话框调试入口 — 委托给共享 DebugSettingsSection。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/debug_settings_section.dart
part of 'settings_dialog.dart';

class _DebugSettingsSection extends ConsumerWidget {
  const _DebugSettingsSection({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DebugSettingsSection(onClose: onClose);
  }
}
