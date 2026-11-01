// 职责: 提供预设宫格与悬停预览的自定义行列选择，并禁用容量不足的规格。
// 关联文件:
//   lib/desktop/features/production/grid/session.dart
//   lib/desktop/features/production/grid/split_bar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../../shared/components/reveric_button.dart';
import '../../../../shared/components/reveric_popover.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../popover.dart';
import 'session.dart';

class ProductionGridSpecPicker extends StatelessWidget {
  const ProductionGridSpecPicker({
    super.key,
    required this.label,
    required this.onSelected,
    this.minimum = 2,
    this.enabled = true,
  });
  final String label;
  final ValueChanged<GridSpec> onSelected;
  final int minimum;
  final bool enabled;
  @override
  Widget build(BuildContext context) => RevericPopover(
    trigger: (_, open, toggle) => RevericButton.text(
      label: label,
      icon: RevericIcons.space_dashboard_outlined,
      size: RevericButtonSize.compact,
      onPressed: enabled ? toggle : null,
    ),
    panel: (_, close) => _Specs(
      minimum: minimum,
      onSelected: (spec) {
        close();
        onSelected(spec);
      },
    ),
  );
}

class _Specs extends HookWidget {
  const _Specs({required this.minimum, required this.onSelected});
  final int minimum;
  final ValueChanged<GridSpec> onSelected;
  @override
  Widget build(BuildContext context) {
    final custom = useState(false);
    final hovered = useState<GridSpec>((rows: 2, cols: 2));
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return ProductionPopoverPanel(
      width: 220,
      maxHeight: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!custom.value)
            for (final side in [2, 3, 4, 5])
              Tooltip(
                message: side * side < minimum
                    ? context.t(LocaleKeys.productionGridCapacity)
                    : '',
                child: RevericButton.text(
                  label: '${side * side} ($side×$side)',
                  onPressed: side * side < minimum
                      ? null
                      : () => onSelected((rows: side, cols: side)),
                ),
              ),
          RevericButton.text(
            label: context.t(LocaleKeys.productionGridCustom),
            onPressed: () => custom.value = !custom.value,
          ),
          if (custom.value) ...[
            Text(
              '${hovered.value.rows}×${hovered.value.cols}',
              textAlign: TextAlign.center,
              style: typo.ui,
            ),
            Padding(
              padding: const EdgeInsets.all(RevericSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 1; row <= 5; row++)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var col = 1; col <= 5; col++)
                          MouseRegion(
                            onEnter: (_) =>
                                hovered.value = (rows: row, cols: col),
                            child: Tooltip(
                              message: row * col < minimum
                                  ? context.t(LocaleKeys.productionGridCapacity)
                                  : '$row×$col',
                              child: InkWell(
                                key: ValueKey('grid-spec/$row/$col'),
                                onTap: row * col < minimum
                                    ? null
                                    : () => onSelected((rows: row, cols: col)),
                                child: Container(
                                  width: RevericSpacing.x3l,
                                  height: RevericSpacing.x3l,
                                  margin: const EdgeInsets.all(
                                    RevericSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        row <= hovered.value.rows &&
                                            col <= hovered.value.cols
                                        ? colors.accent
                                        : colors.surfaceDim,
                                    border: Border.all(
                                      color: colors.borderSubtle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
