// 职责: 画布节点颜色选择行 — 纸色/鲜艳色预设色块 + 自定义颜色；便签与引用节点的详情面板共用
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/desktop/features/canvas/widgets/canvas_sticky_editor.dart
//   lib/shared/theme/canvas_colors.dart
//   lib/shared/models/canvas_layout.dart
//   lib/shared/components/reveric_color_picker_dialog.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/components/reveric_color_picker_dialog.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../canvas_palette.dart';
import 'canvas_node_widget.dart';

const double _swatchSize = 18;
const double _ringWidth = 2;

/// 节点颜色选择行。
///
/// [value] 为 null 表示未着色；[allowNone] 为 true 时多一个「无颜色」色块
/// (引用节点可以不着色，便签总有纸色，不给这个选项)。
class CanvasNodeColorPicker extends StatelessWidget {
  const CanvasNodeColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final value = this.value;
    final custom = value != null && !canvasNodeColorKeys.contains(value)
        ? value
        : null;

    Future<void> pickCustom() async {
      final picked = await showRevericColorPickerDialog(
        context: context,
        initialColor: canvasNodeHueColor(colors, value) ?? colors.accent,
        enableAlpha: false,
      );
      if (picked != null) {
        onChanged(canvasNodeCustomColorValue(picked));
      }
    }

    // 两行：第一行是低饱和纸色与自定义，第二行是鲜艳色。分行后「淡绯」和「红」
    // 这类同色相不同饱和度的色块不会挨在一起难以分辨。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: RevericSpacing.xs,
          runSpacing: RevericSpacing.xs,
          children: [
            if (allowNone)
              _Swatch(
                tooltip: context.t(LocaleKeys.canvasNodeColorNone),
                isActive: value == null,
                onTap: () => onChanged(null),
                child: RevericIcon(
                  RevericIcons.block_outlined,
                  size: 12,
                  color: colors.textSubtle,
                ),
              ),
            for (final key in canvasStickyColorKeys)
              _Swatch(
                tooltip: canvasNodeColorLabel(context, key),
                // 纸色在卡片上本就是淡色，色块也画淡一些，与鲜艳色拉开。
                fill: Color.alphaBlend(
                  canvasNodeHueColor(colors, key)!.withValues(alpha: 0.55),
                  colors.surface,
                ),
                isActive: key == value,
                onTap: () => onChanged(key),
              ),
            if (custom != null)
              _Swatch(
                tooltip: custom,
                fill: canvasNodeHueColor(colors, custom),
                isActive: true,
                onTap: () => unawaited(pickCustom()),
              ),
            _Swatch(
              tooltip: context.t(LocaleKeys.canvasNodeColorCustom),
              isActive: false,
              onTap: () => unawaited(pickCustom()),
              child: RevericIcon(
                RevericIcons.add,
                size: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        Wrap(
          spacing: RevericSpacing.xs,
          runSpacing: RevericSpacing.xs,
          children: [
            for (final key in canvasNodeVividColorKeys)
              _Swatch(
                tooltip: canvasNodeColorLabel(context, key),
                fill: canvasNodeHueColor(colors, key),
                isActive: key == value,
                onTap: () => onChanged(key),
              ),
          ],
        ),
      ],
    );
  }
}

/// 圆形色块；[fill] 为空时画描边空心圆并居中放 [child]。
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.fill,
    this.child,
  });

  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  final Color? fill;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: _swatchSize + _ringWidth * 2 + 2,
          height: _swatchSize + _ringWidth * 2 + 2,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? colors.accent : Colors.transparent,
              width: _ringWidth,
            ),
          ),
          child: Container(
            width: _swatchSize,
            height: _swatchSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: fill == null
                  ? Border.all(color: colors.borderInput)
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
