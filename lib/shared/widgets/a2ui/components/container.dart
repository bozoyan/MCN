// 职责: A2UI 容器组件 Card、Divider 的 builder。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/components/reveric_surfaces.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../components/reveric_surfaces.dart';
import '../../../theme/theme.dart';
import '../component.dart';

Widget buildCard(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  final child = props.child('child');
  return RevericElevatedCard(
    fallback: colors.surface,
    padding: const EdgeInsets.all(RevericSpacing.x2l),
    child: child == null ? const SizedBox.shrink() : buildChild(child),
  );
}

Widget buildDivider(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  if (props.string('axis') == 'vertical') {
    return VerticalDivider(width: 1, thickness: 1, color: colors.borderSubtle);
  }
  return Divider(height: 1, thickness: 1, color: colors.borderSubtle);
}
