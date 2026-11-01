// 职责: 移动端角色选择 Sheet — 承载共享角色选择内容体，返回选中或新建的人物 id。
// 关联文件:
//   lib/shared/widgets/screenplay/character_picker.dart
//   lib/mobile/features/screenplay/scene_editor.dart
//   lib/mobile/features/screenplay/support.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/widgets/screenplay/character_picker.dart';
import 'support.dart';

Future<String?> showMobileScreenplayCharacterPicker(
  BuildContext context, {
  required String databasePath,
  String? selectedId,
  List<String> priorityIds = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.75,
      child: Padding(
        // 搜索框聚焦后键盘会盖住列表，内容整体顶起来。
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileScreenplaySectionHeader(
                title: context.t(LocaleKeys.screenplayCharacterList),
              ),
              Expanded(
                child: ScreenplayCharacterPickerBody(
                  databasePath: databasePath,
                  selectedId: selectedId,
                  priorityIds: priorityIds,
                  autofocus: false,
                  onPick: (id) => Navigator.of(sheetContext).pop(id),
                  onCancel: () => Navigator.of(sheetContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
