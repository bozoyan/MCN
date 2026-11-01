// 职责: 移动端编辑器设置页 — 从章节编辑器「更多」入口进入，复用 shared EditorSettingsSection。
// 关联文件:
//   lib/shared/widgets/settings/editor_settings_section.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/settings/editor_settings_section.dart';

/// 编辑器设置页（全屏）：字体、字号、字距、行高、实体标记、自动排版等。
class MobileEditorSettingsPage extends StatelessWidget {
  const MobileEditorSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        title: Text(
          context.t(LocaleKeys.settingsFonts),
          style: typo.uiSemibold,
        ),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const RevericIcon(RevericIcons.arrow_back, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.md,
          ),
          child: const EditorSettingsSection(),
        ),
      ),
    );
  }
}
