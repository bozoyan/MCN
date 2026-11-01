// 职责: 实体关系图中心点选择 — 用 RevericSelect 指定 BFS 展开与布局根节点。
// 关联文件:
//   lib/shared/components/reveric_select.dart
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/labels.dart
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
import 'colors.dart';
import 'labels.dart';

const double _kCenterSelectWidth = 180;
const double _kCenterSelectMenuWidth = 240;

/// 关系图工具栏中心点选择。
class EntityGraphCenterSelect extends StatelessWidget {
  const EntityGraphCenterSelect({
    super.key,
    required this.centerKey,
    required this.candidateKeys,
    required this.nameMap,
    required this.typeNameMap,
    required this.onChanged,
  });

  final String? centerKey;
  final List<String> candidateKeys;
  final Map<String, String> nameMap;
  final Map<String, String> typeNameMap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return SizedBox(
      width: _kCenterSelectWidth,
      child: RevericSelect<String>(
        value: centerKey,
        height: RevericSizes.fieldHeightSm,
        menuWidth: _kCenterSelectMenuWidth,
        placeholder: context.t(LocaleKeys.entityGraphCenterPlaceholder),
        items: [
          for (final key in candidateKeys)
            RevericSelectItem<String>(
              value: key,
              label: nameMap[key] ?? key,
              subtitle: localizeEntityNodeTypeName(
                context,
                typeNameMap[key] ?? '',
              ),
              color: entityGraphRingColor(
                key.split('_').first,
                colors,
                typeKey: typeNameMap[key],
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
