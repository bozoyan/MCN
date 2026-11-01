// 职责: 实体关系图层数选择 — 用 RevericSelect 切换关系网 BFS 展开深度。
// 关联文件:
//   lib/shared/components/reveric_select.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../components/reveric_select.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

const int kEntityGraphMinDisplayDepth = 1;
const int kEntityGraphMaxDisplayDepth = 5;

/// 与 [RevericSelect] 非 compact 触发器的 caret 尺寸一致。
const double _kCaretIconSize = 13;

/// 与 [RevericSelect] 选中勾尺寸一致，菜单要比触发器略宽以免挤掉文案。
const double _kSelectedCheckSize = 15;

/// 关系图工具栏层数选择。
class EntityGraphDepthSelect extends StatelessWidget {
  const EntityGraphDepthSelect({
    super.key,
    required this.depth,
    required this.onChanged,
  });

  final int depth;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (
        var layer = kEntityGraphMinDisplayDepth;
        layer <= kEntityGraphMaxDisplayDepth;
        layer++
      )
        context.t(
          LocaleKeys.entityGraphDepthLayers,
          namedArgs: {'count': '$layer'},
        ),
    ];
    final textWidth = _longestLabelWidth(context, labels);
    final triggerWidth =
        textWidth +
        RevericSpacing.lg * 2 +
        RevericSpacing.sm +
        _kCaretIconSize +
        RevericSpacing.xxs;
    final menuWidth = triggerWidth + _kSelectedCheckSize + RevericSpacing.sm;

    return SizedBox(
      width: triggerWidth,
      child: RevericSelect<int>(
        value: depth,
        height: RevericSizes.fieldHeightSm,
        menuWidth: menuWidth,
        items: [
          for (final (index, label) in labels.indexed)
            RevericSelectItem<int>(
              value: kEntityGraphMinDisplayDepth + index,
              label: label,
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

double _longestLabelWidth(BuildContext context, List<String> labels) {
  final style = RevericTheme.typographyOf(context).ui;
  final direction = Directionality.of(context);
  var width = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: direction,
    )..layout();
    if (painter.width > width) {
      width = painter.width;
    }
  }
  return width;
}
