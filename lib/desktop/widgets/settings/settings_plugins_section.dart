// 职责: 将共用插件设置嵌入桌面设置内容区。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/plugins/section.dart
import 'package:flutter/widgets.dart';
import '../../../shared/widgets/settings/plugins/section.dart';

class PluginsDesktopSettingsSection extends StatelessWidget {
  const PluginsDesktopSettingsSection({super.key});
  @override
  Widget build(BuildContext context) => const PluginsSettingsSection();
}
