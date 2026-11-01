// 职责: 移动端地图历史抽屉 — 本作品生成过的全部地图图片；点一张关抽屉并进入预览（采用 / 重画）。
// 关联文件:
//   lib/mobile/features/map/studio_page.dart
//   lib/shared/widgets/map/map_history_tab.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/map/map_history_tab.dart';

Future<void> openMobileMapHistorySheet(
  BuildContext context, {
  required String novelId,
  required ValueChanged<AssetRow> onSelected,
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (sheetContext) => SizedBox(
      // 列表是 ListView，需要一个确定的高度。
      height: MediaQuery.of(sheetContext).size.height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x2l,
              0,
              RevericSpacing.x2l,
              RevericSpacing.md,
            ),
            child: Text(
              context.t(LocaleKeys.mapEditorStudioTabHistory),
              style: typo.heading2,
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          Expanded(
            child: SafeArea(
              top: false,
              child: MapHistoryTab(
                novelId: novelId,
                onSelected: (asset) {
                  Navigator.of(sheetContext).pop();
                  onSelected(asset);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
