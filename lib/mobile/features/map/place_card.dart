// 职责: 移动端地图画布上的选中地点浮卡 — 名称与类型，编辑入口，有下级地点时进入它的地图。
// 关联文件:
//   lib/mobile/features/map/studio_page.dart
//   lib/mobile/features/map/location_tree.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import 'location_tree.dart';

class MobileMapPlaceCard extends StatelessWidget {
  const MobileMapPlaceCard({
    super.key,
    required this.location,
    required this.childCount,
    required this.hasMap,
    required this.isCurrentMap,
    required this.onClose,
    required this.onEdit,
    required this.onEnterMap,
  });

  final Location location;
  final int childCount;

  /// 这个地点已经有自己的地图记录：按钮写「打开地图」，否则「新建地图」。
  final bool hasMap;

  /// 选中的就是画布这张图的所属地点，不再给进入入口。
  final bool isCurrentMap;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onEnterMap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final canEnter = childCount > 0 && !isCurrentMap;
    return Container(
      key: const ValueKey('mobile_map_place_card'),
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.lg,
        RevericSpacing.md,
        RevericSpacing.sm,
        RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSemibold,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mobileLocationTypeLabel(location.type, context),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.t(LocaleKeys.commonClose),
                onPressed: onClose,
                icon: RevericIcon(
                  RevericIcons.close,
                  size: 16,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: RevericSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('mobile_map_place_edit'),
                    onPressed: onEdit,
                    icon: const RevericIcon(
                      RevericIcons.edit_outlined,
                      size: 14,
                    ),
                    label: Text(context.t(LocaleKeys.commonEdit)),
                  ),
                ),
                if (canEnter) ...[
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('mobile_map_place_enter'),
                      onPressed: onEnterMap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.accent,
                        side: BorderSide(
                          color: colors.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      icon: const RevericIcon(
                        RevericIcons.map_outlined,
                        size: 14,
                      ),
                      label: Text(
                        context.t(
                          hasMap
                              ? LocaleKeys.mapEditorStudioOpenMap
                              : LocaleKeys.mapEditorStudioNewMap,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
