// 职责: 桌面端中栏壳 — 固定顶栏（返回）→ 作品头 → 分隔线 → 内容区，供侧栏中栏与封面记录栏共用。
// 关联文件:
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/desktop/features/cover_studio/records.dart
//   lib/desktop/widgets/desktop_window_frame.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/desktop-window-frame.md
//   .agents/rules/widget-decomposition.md

import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../desktop_window_frame.dart';

/// 中栏列壳：顶栏 + 作品头 + 分隔线 + 下方内容（分区标题与列表由调用方组装）。
class ContextColumnScaffold extends StatelessWidget {
  const ContextColumnScaffold({
    super.key,
    required this.novelHeader,
    required this.child,
    this.onBack,
    this.backButtonKey,
    this.trailing,
    this.leadingInset = 0,
  });

  /// 离开当前页/编辑器的返回；为 null 时不渲染返回钮。
  final VoidCallback? onBack;

  /// 测试或调用方定位返回钮用。
  final Key? backButtonKey;

  /// 顶栏右侧动作（侧栏折叠 / 封面关闭等）。
  final Widget? trailing;

  /// 顶栏左侧额外 inset（侧栏中栏需补齐红绿灯避让的剩余量）。
  final double leadingInset;

  /// 作品头（侧栏含切换菜单；封面可为只读头像+书名）。
  final Widget novelHeader;

  /// 分区标题 + 列表等主体。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: DesktopWindowFrame.titleBarHeight,
          child: Padding(
            padding: EdgeInsets.only(
              left: RevericSpacing.sm + leadingInset,
              right: RevericSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onBack != null)
                  Tooltip(
                    message: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    child: InkWell(
                      key: backButtonKey,
                      onTap: onBack,
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                      hoverColor: colors.hover,
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.xs),
                        child: RevericIcon(
                          RevericIcons.chevron_left,
                          size: 20,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
        ),
        novelHeader,
        Divider(height: RevericSizes.dividerThickness, color: colors.border),
        Expanded(child: child),
      ],
    );
  }
}

/// 中栏分区标题行：标题 + 数量 + 可选动作。
class ContextColumnSectionHeader extends StatelessWidget {
  const ContextColumnSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.useProminentMetrics = false,
    this.actions = const [],
  });

  final String title;
  final int count;
  final bool useProminentMetrics;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.only(
        left: RevericSpacing.x2l,
        right: RevericSpacing.sm,
        top: RevericSpacing.xs,
        bottom: RevericSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            '$count',
            style: (useProminentMetrics ? typo.uiSmall : typo.uiTiny).copyWith(
              color: colors.textSubtle,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: RevericSpacing.xs),
            ...actions,
          ] else
            const SizedBox(width: RevericSpacing.sm),
        ],
      ),
    );
  }
}
