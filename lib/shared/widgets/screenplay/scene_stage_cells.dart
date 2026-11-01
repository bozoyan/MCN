// 职责: 用一排小格展示一集各场次的定稿状态（实心 = 定稿）。
// 关联文件:
//   lib/desktop/features/screenplay/overview_cards.dart
//   lib/mobile/features/screenplay/episode_card.dart
//   lib/shared/models/screenplay.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../models/screenplay.dart';
import '../../theme/theme.dart';

class ScreenplaySceneStageCells extends StatelessWidget {
  const ScreenplaySceneStageCells({super.key, required this.scenes});

  final List<ScreenplaySceneSummary> scenes;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final scene in scenes)
          Container(
            width: 14,
            height: 8,
            decoration: BoxDecoration(
              color: scene.stage == screenplayStageFinal ? colors.accent : null,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: scene.stage == screenplayStageFinal
                    ? colors.accent
                    : colors.border,
              ),
            ),
          ),
      ],
    );
  }
}
