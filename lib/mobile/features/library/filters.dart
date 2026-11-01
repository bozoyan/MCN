// 职责: 移动书架的集合行 — 左侧横滑集合标签（末尾新建集合），右端固定「筛选与排序」入口，滚动时吸顶。
// 关联文件:
//   lib/mobile/pages/library_page.dart
//   lib/mobile/features/library/shelf_options_sheet.dart
//   lib/shared/widgets/collections/shelf.dart
//   lib/shared/widgets/collections/location.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/home.json
//   assets/translations/zh-CN/home.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/collections/location.dart';
import '../../../shared/widgets/collections/shelf.dart';

const double _rowHeight = 44;

class MobileCollectionRowDelegate extends SliverPersistentHeaderDelegate {
  const MobileCollectionRowDelegate({
    required this.location,
    required this.filterActive,
    required this.onOpenFilter,
  });
  final CollectionLocation location;

  /// 分类或排序偏离默认值时高亮入口，提示列表已被收窄或重排。
  final bool filterActive;
  final VoidCallback onOpenFilter;

  @override
  double get minExtent => _rowHeight + 1;
  @override
  double get maxExtent => _rowHeight + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(child: CollectionTabs(location: location)),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 12),
            color: colors.borderSubtle,
          ),
          Tooltip(
            message: context.t(LocaleKeys.homeFilterAndSort),
            child: InkWell(
              onTap: onOpenFilter,
              child: SizedBox(
                width: 52,
                height: _rowHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RevericIcon(
                      RevericIcons.tune,
                      size: 20,
                      color: filterActive
                          ? colors.accent
                          : colors.textSecondary,
                      semanticLabel: context.t(LocaleKeys.homeFilterAndSort),
                    ),
                    if (filterActive)
                      Positioned(
                        top: 10,
                        right: 13,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(MobileCollectionRowDelegate oldDelegate) => true;
}
