// 职责: Reveric 下拉控件 — 提供表单、数字范围与设置/属性面板 inline dropdown。
// 关联文件:
//   lib/shared/components/reveric_input_decoration.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'reveric_input_decoration.dart';

class RevericInlineDropdownItem<T> {
  const RevericInlineDropdownItem({
    required this.value,
    required this.child,
    this.selectedChild,
  });

  final T value;
  final Widget child;
  final Widget? selectedChild;
}

class RevericFormDropdown<T> extends StatelessWidget {
  const RevericFormDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.isExpanded = false,
    this.suffixText,
    this.prefixIcon,
    this.prefixIconConstraints,
    this.selectedItemBuilder,
    this.dropdownColor,
    this.contentPadding,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final String? errorText;
  final bool isExpanded;
  final String? suffixText;

  /// 触发器前置图标；传入时一并给 [prefixIconConstraints]，否则会被撑到 48×48。
  final Widget? prefixIcon;
  final BoxConstraints? prefixIconConstraints;
  final DropdownButtonBuilder? selectedItemBuilder;
  final Color? dropdownColor;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return DropdownButtonFormField<T>(
      isExpanded: isExpanded,
      initialValue: value,
      decoration: revericInputDecoration(
        context,
        label: label,
        hintText: hintText,
        errorText: errorText,
        suffixText: suffixText,
        prefixIcon: prefixIcon,
        prefixIconConstraints: prefixIconConstraints,
        contentPadding: contentPadding,
      ),
      dropdownColor: dropdownColor ?? colors.surface,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      icon: RevericIcon(
        RevericIcons.expand_more,
        size: 14,
        color: colors.textMuted,
      ),
      items: items,
      onChanged: onChanged,
      selectedItemBuilder: selectedItemBuilder,
    );
  }
}

class RevericNumberDropdown extends StatelessWidget {
  const RevericNumberDropdown({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label,
    this.suffix,
    this.enabled = true,
  }) : assert(min <= max);

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? label;
  final String? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = value < min
        ? min
        : value > max
        ? max
        : value;
    final values = [for (var item = min; item <= max; item += 1) item];
    return RevericFormDropdown<int>(
      value: effectiveValue,
      label: label,
      suffixText: suffix,
      items: [
        for (final item in values)
          DropdownMenuItem<int>(value: item, child: Text(item.toString())),
      ],
      onChanged: enabled
          ? (next) {
              if (next != null) {
                onChanged(next);
              }
            }
          : null,
    );
  }
}

class RevericInlineDropdown<T> extends StatelessWidget {
  const RevericInlineDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelTooltip,
    this.unsetLabel,
    this.emptyMessage,
    this.enabled = true,
    this.dense = false,
  });

  final String label;
  final String? labelTooltip;
  final T? value;
  final List<RevericInlineDropdownItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? unsetLabel;
  final String? emptyMessage;
  final bool enabled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final labelStyle = dense
        ? typo.uiTiny.copyWith(
            color: enabled ? colors.textSubtle : colors.textMuted,
          )
        : typo.uiSemibold.copyWith(
            color: enabled ? colors.textPrimary : colors.textMuted,
          );

    final body = items.isEmpty && emptyMessage != null
        ? _RevericInlineDropdownEmptyMessage(
            message: emptyMessage!,
            dense: dense,
          )
        : _RevericInlineDropdownBody<T>(
            value: _effectiveValue,
            items: items,
            onChanged: enabled ? onChanged : null,
            unsetLabel: unsetLabel,
            dense: dense,
          );

    final labelWidget = labelTooltip == null
        ? Text(label, style: labelStyle)
        : Tooltip(
            message: labelTooltip!,
            child: Text(label, style: labelStyle),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget,
        const SizedBox(height: RevericSpacing.xs),
        body,
      ],
    );
  }

  T? get _effectiveValue {
    if (items.any((item) => item.value == value)) {
      return value;
    }
    return null;
  }
}

class _RevericInlineDropdownEmptyMessage extends StatelessWidget {
  const _RevericInlineDropdownEmptyMessage({
    required this.message,
    required this.dense,
  });

  final String message;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? RevericSpacing.sm : RevericSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.borderInput),
      ),
      child: Text(message, style: typo.ui.copyWith(color: colors.textMuted)),
    );
  }
}

class _RevericInlineDropdownBody<T> extends StatelessWidget {
  const _RevericInlineDropdownBody({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.unsetLabel,
    required this.dense,
  });

  final T? value;
  final List<RevericInlineDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? unsetLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final horizontalPadding = dense ? RevericSpacing.sm : RevericSpacing.md;
    final minHeight = dense
        ? RevericSizes.buttonHeightSm
        : RevericSizes.buttonHeight;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.borderInput),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          isExpanded: true,
          isDense: true,
          value: value,
          dropdownColor: colors.surface,
          icon: RevericIcon(
            RevericIcons.expand_more,
            size: 14,
            color: colors.textMuted,
          ),
          items: [
            if (unsetLabel != null)
              DropdownMenuItem<T?>(
                value: null,
                child: Text(
                  unsetLabel!,
                  style: typo.ui.copyWith(color: colors.textMuted),
                ),
              ),
            for (final item in items)
              DropdownMenuItem<T?>(value: item.value, child: item.child),
          ],
          selectedItemBuilder: (context) {
            return [
              if (unsetLabel != null)
                _RevericDropdownSelectedItem(
                  child: Text(
                    unsetLabel!,
                    style: typo.ui.copyWith(color: colors.textMuted),
                  ),
                ),
              for (final item in items)
                _RevericDropdownSelectedItem(
                  child: item.selectedChild ?? item.child,
                ),
            ];
          },
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RevericDropdownSelectedItem extends StatelessWidget {
  const _RevericDropdownSelectedItem({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerLeft, child: child);
  }
}
