// 职责: 绘制移动端等宽分段导航，使用浅底与无阴影的滑动选中块。
// 关联文件:
//   lib/mobile/widgets/segmented_tab_switcher.dart
//   lib/mobile/pages/library_page.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import '../../shared/theme/theme.dart';

class MobileSegmentedTabs extends StatelessWidget {
  const MobileSegmentedTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    assert(
      tabs.isNotEmpty && selectedIndex >= 0 && selectedIndex < tabs.length,
    );
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.button),
      ),
      padding: const EdgeInsets.all(RevericSpacing.xxs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: tabWidth * selectedIndex,
                width: tabWidth,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.selected,
                    borderRadius: BorderRadius.circular(RevericRadius.capsule),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selectedIndex,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onSelected(i),
                            borderRadius: BorderRadius.circular(
                              RevericRadius.capsule,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: RevericSpacing.sm,
                              ),
                              child: AnimatedDefaultTextStyle(
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                style:
                                    (i == selectedIndex
                                            ? typo.uiSemibold
                                            : typo.ui)
                                        .copyWith(
                                          color: i == selectedIndex
                                              ? colors.textPrimary
                                              : colors.textMuted,
                                        ),
                                child: Text(
                                  tabs[i],
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
