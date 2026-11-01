// 职责: 在桌面设置内容区就地切换 MCP 服务列表与编辑表单。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/mcp/section.dart
//   lib/shared/widgets/settings/mcp/server_editor.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/models/mcp/config.dart';
import '../../../shared/widgets/settings/mcp/section.dart';
import '../../../shared/widgets/settings/mcp/server_editor.dart';

class McpDesktopSettingsSection extends HookWidget {
  const McpDesktopSettingsSection({super.key});
  @override
  Widget build(BuildContext context) {
    // 外层为空表示在看列表；内层 config 为空表示新建。
    final editing = useState<({McpServerConfig? config})?>(null);
    final target = editing.value;
    if (target == null) {
      return McpSettingsSection(
        onEdit: (config) => editing.value = (config: config),
      );
    }
    return McpServerEditor(
      key: ValueKey(target.config?.name),
      config: target.config,
      onClose: () => editing.value = null,
    );
  }
}
