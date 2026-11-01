// 职责: 移动端详情编辑页共享标题栏 — 返回、居中标题 + 副标题/保存状态、右侧 redo/undo（作用于当前焦点字段）。
// 关联文件:
//   lib/mobile/pages/outline_editor_page.dart
//   lib/mobile/pages/character_editor_page.dart
//   lib/mobile/pages/foreshadowing_editor_page.dart
//   lib/mobile/pages/location_editor_page.dart
//   lib/mobile/pages/entry_editor_page.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../shared/components/reveric_icon_button.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';

/// 移动端详情编辑页标题栏。
///
/// [undoController] 由调用方在页内创建并共享给所有 `TextField` /
/// `RevericMarkdownEditor`，redo/undo 按钮作用于当前持有焦点的字段。
/// 按钮可用性跟随 `UndoHistoryController.value` 的 `canUndo/canRedo`。
class MobileEditorAppBar extends StatelessWidget {
  const MobileEditorAppBar({
    super.key,
    required this.title,
    required this.saving,
    required this.savedAt,
    required this.onBack,
    required this.undoController,
    this.subtitle,
    this.backButtonKey,
  });

  /// 主标题（通常为实体名称）。
  final String title;

  /// 副标题（如角色定位、分区名）；与保存状态以「 · 」拼接展示。
  final String? subtitle;
  final bool saving;
  final DateTime? savedAt;
  final VoidCallback onBack;
  final UndoHistoryController undoController;

  /// 返回按钮的可选 Key（如测试定位需要）。
  final Key? backButtonKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final saveStatus = saving
        ? context.t(LocaleKeys.mobileEditorSaving)
        : (savedAt != null ? context.t(LocaleKeys.commonSaved) : '');
    final subtitleParts = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (saveStatus.isNotEmpty) saveStatus,
    ];
    final subtitleLine = subtitleParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.xs,
        RevericSpacing.sm,
        RevericSpacing.xs,
        RevericSpacing.sm,
      ),
      child: Row(
        children: [
          RevericIconButton(
            key: backButtonKey,
            icon: RevericIcons.arrow_back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                if (subtitleLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          // redo/undo 作用于当前焦点字段；可用性跟随共享 controller 状态。
          AnimatedBuilder(
            animation: undoController,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIconButton(
                    icon: RevericIcons.arrow_counter_clockwise,
                    tooltip: context.t(LocaleKeys.workspaceUndo),
                    onPressed: undoController.value.canUndo
                        ? undoController.undo
                        : null,
                  ),
                  RevericIconButton(
                    icon: RevericIcons.arrow_clockwise,
                    tooltip: context.t(LocaleKeys.workspaceRedo),
                    onPressed: undoController.value.canRedo
                        ? undoController.redo
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
