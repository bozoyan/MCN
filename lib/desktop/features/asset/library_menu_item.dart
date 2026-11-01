// 职责: 生成「加入 / 移出资产库」菜单项，按资产当前是否在库切换文案与图标。
// 关联文件:
//   lib/shared/database/daos/asset_dao.dart
//   lib/desktop/features/production/node_bar.dart
//   lib/desktop/features/production/asset_picker.dart
//   lib/desktop/features/editing/assets.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import 'package:flutter/widgets.dart';
import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

/// 只切换资产库标记；文件和已有引用不受影响。
RevericMenuItem assetLibraryMenuItem(
  BuildContext context, {
  required AssetRow asset,
  required VoidCallback onToggle,
}) => RevericMenuItem(
  icon: asset.inLibrary
      ? RevericIcons.tray_arrow_up
      : RevericIcons.tray_arrow_down,
  label: context.t(
    asset.inLibrary
        ? LocaleKeys.productionRemoveFromLibrary
        : LocaleKeys.productionAddToLibrary,
  ),
  onTap: onToggle,
);
