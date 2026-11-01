// 职责: 移动端等宽分段 tab — 滑动指示器 + 方向性内容切换动效。
// 关联文件:
//   lib/mobile/widgets/segmented_tabs.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../shared/theme/theme.dart';
import 'segmented_tabs.dart';

/// 方向性 fade + slide，供 [MobileSegmentedTabSwitcher] 与页面级 tab 内容复用。
Widget mobileTabSwitchTransition(
  Widget child,
  Animation<double> animation,
  int slideDirection,
) {
  final slide =
      Tween<Offset>(
        begin: Offset(0.06 * slideDirection, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(position: slide, child: child),
  );
}

/// 等宽分段 tab：顶部滑动 pill + [AnimatedSwitcher] 内容区。
class MobileSegmentedTabSwitcher extends HookWidget {
  const MobileSegmentedTabSwitcher({
    super.key,
    required this.tabs,
    required this.children,
    this.initialIndex = 0,
  });

  final List<String> tabs;
  final List<Widget> children;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    assert(tabs.length == children.length);
    final selectedTab = useState(initialIndex);
    final slideDirection = useRef(1);

    void selectTab(int index) {
      final prev = selectedTab.value;
      if (index != prev) {
        slideDirection.value = index > prev ? 1 : -1;
      }
      selectedTab.value = index;
    }

    return Column(
      children: [
        MobileSegmentedTabs(
          tabs: tabs,
          selectedIndex: selectedTab.value,
          onSelected: selectTab,
        ),
        const SizedBox(height: RevericSpacing.sm),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => mobileTabSwitchTransition(
              child,
              animation,
              slideDirection.value,
            ),
            child: KeyedSubtree(
              key: ValueKey<int>(selectedTab.value),
              child: children[selectedTab.value],
            ),
          ),
        ),
      ],
    );
  }
}
