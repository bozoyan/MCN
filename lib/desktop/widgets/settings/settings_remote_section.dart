// 职责: 桌面端设置对话框远程桥接入口 — 委托给共享 RemoteBridgeSettingsSection
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/remote_bridge_settings_section.dart
part of 'settings_dialog.dart';

class _RemoteSettingsSection extends StatelessWidget {
  const _RemoteSettingsSection();

  @override
  Widget build(BuildContext context) {
    return RemoteBridgeSettingsSection();
  }
}
