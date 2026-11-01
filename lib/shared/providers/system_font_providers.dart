// 职责: 系统字体 Provider — 缓存桌面系统字体族列表供设置页选择。
// 关联文件:
//   lib/shared/services/system_font_service.dart
//   lib/desktop/widgets/settings/settings_editor_section.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../services/system_font_service.dart';

final systemFontServiceProvider = Provider<SystemFontService>((ref) {
  return SystemFontService();
});

final systemFontFamiliesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  return ref.watch(systemFontServiceProvider).listFontFamilies();
});
