// 职责: 风格库弹层 — 按分类和名称挑选预设或自定义风格，支持跟随剧本、无风格和就地新建 / 编辑自定义风格。
// 关联文件:
//   lib/desktop/features/production/style_thumb.dart
//   lib/desktop/features/production/popover.dart
//   lib/desktop/features/production/style_editor.dart
//   lib/shared/models/production/style.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/search-debounce.md
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/production/style.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/theme/theme.dart';
import 'popover.dart';
import 'style_editor.dart';
import 'style_thumb.dart';

/// 左侧分类栏：null 表示全部。
const _categories = <ProductionStyleCategory?>[
  null,
  ProductionStyleCategory.live_action,
  ProductionStyleCategory.two_d,
  ProductionStyleCategory.three_d,
  ProductionStyleCategory.custom,
];

String _categoryLabel(BuildContext context, ProductionStyleCategory? c) =>
    context.t(switch (c) {
      null => LocaleKeys.commonFilterAll,
      ProductionStyleCategory.live_action =>
        LocaleKeys.productionStyleLiveAction,
      ProductionStyleCategory.two_d => LocaleKeys.productionStyleTwoD,
      ProductionStyleCategory.three_d => LocaleKeys.productionStyleThreeD,
      ProductionStyleCategory.custom => LocaleKeys.productionStyleCustom,
    });

class ProductionStylePicker extends HookWidget {
  const ProductionStylePicker({
    super.key,
    required this.service,
    required this.value,
    required this.onPick,
    required this.onClose,
    this.screenplay,
  });
  final ProductionCanvasService service;
  final ProductionStyleChoice value;
  final ValueChanged<ProductionStyleChoice> onPick;
  final VoidCallback onClose;

  /// 节点上打开时传剧本当前的风格，第一张卡片是「跟随剧本 · 名称」；剧本顶栏不传。
  final ProductionStyleLook? screenplay;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();
    final category = useState<ProductionStyleCategory?>(null);
    final editing = useState<({bool open, ProductionStyleRow? style})>((
      open: false,
      style: null,
    ));
    final styles = useStream(
      useMemoized(
        () => service.library.database.productionStyleDao.watchStyles(),
        [service],
      ),
    );
    bool matches(String name) => name.toLowerCase().contains(search.query);
    final presets = category.value == ProductionStyleCategory.custom
        ? const <ProductionStylePreset>[]
        : builtinProductionStyles
              .where(
                (p) =>
                    (category.value == null || p.category == category.value) &&
                    matches(p.name),
              )
              .toList();
    final all = category.value == null;
    final showCustom = all || category.value == ProductionStyleCategory.custom;
    final custom = showCustom
        ? (styles.data ?? const <ProductionStyleRow>[])
              .where((a) => matches(a.name))
              .toList()
        : const <ProductionStyleRow>[];
    final height = math.min(
      RevericSizes.productionStylePickerHeight,
      MediaQuery.sizeOf(context).height * .8,
    );

    Widget grid() => LayoutBuilder(
      builder: (context, constraints) {
        const gap = RevericSpacing.md;
        const preferredWidth =
            (RevericSizes.productionStylePickerWidth -
                RevericSizes.productionStyleCategoryWidth -
                RevericSpacing.xl * 2 -
                gap * 3) /
            4;
        final columns =
            ((constraints.maxWidth - RevericSpacing.xl * 2 + gap) /
                    (preferredWidth + gap))
                .floor()
                .clamp(1, 4);
        // 向下取整，避免浮点误差让最后一列挤到下一行。
        final width =
            ((constraints.maxWidth -
                        RevericSpacing.xl * 2 -
                        gap * (columns - 1)) /
                    columns)
                .floorToDouble();
        Widget cell(Widget child) => SizedBox(width: width, child: child);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.xl,
            RevericSpacing.xxs,
            RevericSpacing.xl,
            RevericSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: RevericSpacing.lg,
                children: [
                  // 跟随剧本 / 无风格不属于任何分类，只在「全部」里出现。
                  if (screenplay case final screenplay? when all)
                    cell(
                      _StyleCard(
                        selected: value is InheritedProductionStyle,
                        thumb: ProductionStyleThumb(
                          kind: screenplay.kind,
                          seed: screenplay.seed,
                          iconSize: 30,
                        ),
                        label: context.t(LocaleKeys.productionStyleInherit),
                        detail: screenplay.label,
                        onTap: () => onPick(const InheritedProductionStyle()),
                      ),
                    ),
                  if (all)
                    cell(
                      _StyleCard(
                        selected: value is NoProductionStyle,
                        thumb: const ProductionStyleThumb(
                          kind: ProductionStyleThumbKind.none,
                          iconSize: 30,
                        ),
                        label: context.t(LocaleKeys.productionStyleNone),
                        onTap: () => onPick(const NoProductionStyle()),
                      ),
                    ),
                  if (showCustom)
                    cell(
                      _StyleCard(
                        selected: false,
                        thumb: const ProductionStyleThumb(
                          kind: ProductionStyleThumbKind.create,
                          iconSize: 28,
                        ),
                        label: context.t(
                          LocaleKeys.productionStyleCustomPrompt,
                        ),
                        onTap: () => editing.value = (open: true, style: null),
                      ),
                    ),
                  for (final style in custom)
                    cell(
                      _StyleCard(
                        selected: value.stored == style.id,
                        thumb: const ProductionStyleThumb(
                          kind: ProductionStyleThumbKind.custom,
                          iconSize: 28,
                        ),
                        label: style.name,
                        onTap: () => onPick(CustomProductionStyle(style.id)),
                        onEdit: () =>
                            editing.value = (open: true, style: style),
                      ),
                    ),
                  for (final preset in presets)
                    cell(
                      _StyleCard(
                        selected:
                            value.stored ==
                            '$productionStylePresetPrefix${preset.id}',
                        thumb: ProductionStyleThumb(
                          kind: ProductionStyleThumbKind.preset,
                          seed: preset.id,
                        ),
                        label: preset.name,
                        onTap: () => onPick(PresetProductionStyle(preset.id)),
                      ),
                    ),
                ],
              ),
              if (search.active && presets.isEmpty && custom.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: RevericSpacing.x4l),
                  child: Text(
                    context.t(LocaleKeys.commonNoResults),
                    textAlign: TextAlign.center,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );

    return ProductionPopoverPanel(
      width: RevericSizes.productionStylePickerWidth,
      maxHeight: height,
      radius: RevericRadius.pill,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: editing.value.open
            ? ProductionStyleEditor(
                style: editing.value.style,
                onClose: () => editing.value = (open: false, style: null),
                onDismiss: onClose,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RevericSpacing.md,
                      RevericSpacing.md,
                      RevericSpacing.md,
                      RevericSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: RevericSearchField(
                            controller: search.controller,
                            hint: context.t(LocaleKeys.productionStyleSearch),
                            outlined: false,
                          ),
                        ),
                        RevericIconButton(
                          icon: RevericIcons.close,
                          tooltip: context.t(LocaleKeys.commonClose),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: RevericSizes.productionStyleCategoryWidth,
                          padding: const EdgeInsets.fromLTRB(
                            RevericSpacing.md,
                            RevericSpacing.xxs,
                            RevericSpacing.md,
                            RevericSpacing.xl,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: colors.borderSubtle),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final c in _categories)
                                _CategoryItem(
                                  label: _categoryLabel(context, c),
                                  selected: category.value == c,
                                  onTap: () => category.value = c,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: styles.hasError
                              ? Center(
                                  child: Text(
                                    context.t(LocaleKeys.productionFailed),
                                    style: typo.uiSmall.copyWith(
                                      color: colors.textMuted,
                                    ),
                                  ),
                                )
                              : grid(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 分类栏的一行：圆点 + 名称，选中时加粗、圆点不透明。
class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final color = selected ? colors.textPrimary : colors.textMuted;
    return InkWell(
      onTap: onTap,
      hoverColor: colors.hover,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            const SizedBox(width: RevericSpacing.sm),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: selected ? 1 : .6),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (selected ? typo.uiSmallSemibold : typo.uiSmall)
                    .copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 风格卡片：16:9 预览 + 名称。选中时深色描边 + 对勾；自定义风格悬停时显示编辑按钮。
class _StyleCard extends HookWidget {
  const _StyleCard({
    required this.selected,
    required this.thumb,
    required this.label,
    required this.onTap,
    this.detail,
    this.onEdit,
  });
  final bool selected;
  final Widget thumb;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hover = useState(false);
    final radius = BorderRadius.circular(RevericRadius.large);
    return MouseRegion(
      onEnter: (_) => hover.value = true,
      onExit: (_) => hover.value = false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected
                        ? colors.textPrimary
                        : hover.value
                        ? colors.borderInput
                        : colors.borderSubtle,
                    width: selected ? 2 : 1,
                  ),
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: radius,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: radius, child: thumb),
                    if (selected)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.textPrimary.withValues(alpha: .6),
                          ),
                          child: Center(
                            child: RevericIcon(
                              RevericIcons.check,
                              size: 11,
                              color: colors.onAccent,
                            ),
                          ),
                        ),
                      ),
                    if (onEdit != null && hover.value)
                      Positioned(
                        left: RevericSpacing.xxs,
                        bottom: RevericSpacing.xxs,
                        child: Material(
                          color: colors.surface,
                          shape: const CircleBorder(),
                          child: RevericIconButton(
                            icon: RevericIcons.edit_outlined,
                            tooltip: context.t(LocaleKeys.commonEdit),
                            onPressed: onEdit,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: ' · $detail',
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (selected ? typo.uiSmallSemibold : typo.uiSmall)
                    .copyWith(
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
