// 职责: 移动端书架「筛选与排序」Sheet — 分类单选只作用于当前集合，排序是页面状态、切集合沿用；点选即时生效。
// 关联文件:
//   lib/mobile/features/library/filters.dart
//   lib/mobile/pages/library_page.dart
//   lib/shared/models/novel.dart
//   lib/shared/widgets/novel/library_shelf_labels.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/home.json
//   assets/translations/zh-CN/home.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_filter_chip.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/novel/library_shelf_labels.dart';

/// [novels] 为当前集合（未按分类过滤）的作品，用来算各分类的计数；分类为 null 表示全部。
Future<void> showMobileShelfOptionsSheet(
  BuildContext context, {
  required List<Novel> novels,
  required String? contentKind,
  required LibrarySortOrder sortOrder,
  required ValueChanged<LibrarySortOrder> onSortChanged,
  required String? category,
  required ValueChanged<String?> onCategoryChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShelfOptionsSheet(
      novels: novels,
      contentKind: contentKind,
      sortOrder: sortOrder,
      onSortChanged: onSortChanged,
      category: category,
      onCategoryChanged: onCategoryChanged,
    ),
  );
}

class _ShelfOptionsSheet extends HookWidget {
  const _ShelfOptionsSheet({
    required this.novels,
    required this.contentKind,
    required this.sortOrder,
    required this.onSortChanged,
    required this.category,
    required this.onCategoryChanged,
  });

  final List<Novel> novels;

  /// 作品区的类型筛选，决定能不能按字数排。
  final String? contentKind;
  final LibrarySortOrder sortOrder;
  final ValueChanged<LibrarySortOrder> onSortChanged;
  final String? category;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // Sheet 是独立路由，父页面重建不会带动这里，本地镜像一份选中态。
    final sort = useState(sortOrder);
    final selectedCategory = useState(category);
    final categoryCounts = novels.categoryCounts;
    final dirty =
        selectedCategory.value != null ||
        sort.value != LibrarySortOrder.updated;

    void pickSort(LibrarySortOrder value) {
      sort.value = value;
      onSortChanged(value);
    }

    void pickCategory(String? value) {
      selectedCategory.value = value;
      onCategoryChanged(value);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: RevericSpacing.x3l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x3l,
              0,
              RevericSpacing.md,
              RevericSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.homeFilterAndSort),
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (dirty)
                  TextButton(
                    onPressed: () {
                      pickCategory(null);
                      pickSort(LibrarySortOrder.updated);
                    },
                    child: Text(context.t(LocaleKeys.commonReset)),
                  ),
              ],
            ),
          ),
          if (categoryCounts.length > 1 || selectedCategory.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x3l,
              ),
              child: _Section(
                title: context.t(LocaleKeys.libraryCategory),
                children: [
                  RevericFilterChip(
                    label: libraryCategoryText(context, null),
                    count: novels.length,
                    selected: selectedCategory.value == null,
                    onTap: () => pickCategory(null),
                  ),
                  for (final MapEntry(key: c, value: count)
                      in categoryCounts.entries)
                    RevericFilterChip(
                      label: libraryCategoryText(context, c),
                      count: count,
                      selected: selectedCategory.value == c,
                      onTap: () => pickCategory(c),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x3l,
              0,
              RevericSpacing.x3l,
              RevericSpacing.xs,
            ),
            child: Text(
              context.t(LocaleKeys.homeSort),
              style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
            ),
          ),
          for (final order in librarySortOrdersFor(contentKind))
            ListTile(
              title: Text(
                librarySortText(context, order),
                style: (sort.value == order ? typo.uiSemibold : typo.ui)
                    .copyWith(
                      color: sort.value == order
                          ? colors.accent
                          : colors.textPrimary,
                    ),
              ),
              trailing: sort.value == order
                  ? RevericIcon(
                      RevericIcons.check,
                      size: 18,
                      color: colors.accent,
                    )
                  : null,
              onTap: () => pickSort(order),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.md),
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: children,
          ),
        ],
      ),
    );
  }
}
