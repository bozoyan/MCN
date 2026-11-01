// 职责: 组合移动端整集剧本区域并转交保存注册。
// 关联文件:
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/services/document_save_coordinator.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/screenplay_element.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/database/app_database.dart';
import 'document.dart';

export 'scene_editor.dart';

class MobileScreenplayScriptPage extends ConsumerWidget {
  const MobileScreenplayScriptPage({
    super.key,
    required this.novel,
    required this.registerFlush,
    required this.onOpenAssistant,
  });
  final Novel novel;
  final ValueChanged<Future<void> Function()?> registerFlush;
  final VoidCallback onOpenAssistant;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MobileScreenplayDocument(
      novel: novel,
      registerFlush: registerFlush,
      onOpenAssistant: onOpenAssistant,
    );
  }
}
