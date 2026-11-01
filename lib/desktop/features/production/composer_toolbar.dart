// 职责: 按内容排列生成输入栏的选项，窄窗口换行，并把提交按钮固定在右侧。
// 关联文件:
//   lib/desktop/features/production/composer.dart
//   lib/desktop/features/production/image_composer.dart
//   lib/desktop/features/production/popover.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import '../../../shared/theme/theme.dart';

class ProductionComposerToolbar extends StatelessWidget {
  const ProductionComposerToolbar({
    super.key,
    required this.children,
    required this.submit,
  });

  final List<Widget> children;
  final Widget submit;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: RevericSpacing.sm,
          children: children,
        ),
      ),
      const SizedBox(width: RevericSpacing.sm),
      submit,
    ],
  );
}
